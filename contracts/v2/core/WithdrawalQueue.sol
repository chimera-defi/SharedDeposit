// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {FIFOQueue} from "../lib/FIFOQueue.sol";
import {Errors} from "../lib/Errors.sol";
import {OperatorSettable} from "../lib/OperatorSettable.sol";
import {GranularPause} from "../lib/GranularPause.sol";
import {SharedDepositMinterV2} from "./SharedDepositMinterV2.sol";

/**
 * @title WithdrawalQueue
 * @notice ERC-7540 inspired withdrawal contract with FIFO queue and epoch delay
 * @author @ChimeraDefi - chimera_defi@protonmail.com | sharedstake.org
 * @dev -
 * ERC-7540 inspired withdrawal contract
 * Supports two modes based on deployment parameters:
 * - ERC4626 mode (virtualPrice = 0): For WSGETH tokens using dynamic exchange rates via IERC4626
 * - Fixed price mode (virtualPrice > 0): For VETH2 tokens using fixed virtual price
 * This contract is designed to be used with SharedDepositMinterV2 contract (ERC4626 mode)
 * or as standalone for VETH2 (fixed price mode)
 * As a module extension that adds 7540 methods requestRedeem and redeem
 * Example flow ->
 * user calls requestRedeem(userShares)
 * user calls setOperator(admin OR protocol provided keeper, true)
 * admin can now call redeemFor on the users behalf if needed after epoch
 * user calls redeem(userShares, receiver) after waiting for epoch
 * Caveats:
 * If the user requests another redemption, before fulfillment,
 * this resets the epoch length clock for their request
 * Basic upgrade path:
 * 1. Call togglePause(1), this disables the requestRedeem fn so no new requests
 * 2. Deploy new contract, direct users to it
 * 3. Fulfill any remaining redeemRequests i.e. totalPendingRequest,
 * for all RedeemRequest events from requestsFulfilled to requestsCreated
 */
contract WithdrawalQueue is AccessControl, ReentrancyGuard, GranularPause, FIFOQueue, OperatorSettable {
    using Address for address payable;

    struct Request {
        address requester;
        uint256 shares;
    }
    // SharedDepositMinterV2 public immutable MINTER;
    address public immutable MINTER;
    address public immutable UNDERLYING; // WSGETH or VETH2 token address
    uint256 public immutable VIRTUAL_PRICE; // 0 = use ERC4626 mode, non-zero = use fixed price mode

    uint256 internal totalPendingRequest;
    uint256 internal requestsCreated;
    uint256 internal requestsFulfilled;
    uint256 public totalAssetsOut;

    bytes32 public constant GOV = keccak256("GOV"); // Governance for settings - normally timelock controlled by multisig

    mapping(uint256 => Request) internal requests;
    mapping(address => uint256) public redeemRequests;

    event RedeemRequest(
        address indexed requester,
        address indexed owner,
        uint256 indexed requestId,
        address operator,
        uint256 assets
    );
    event Redeem(address indexed requester, address indexed receiver, uint256 shares, uint256 assets);
    event CancelRedeem(address indexed requester, address indexed receiver, uint256 shares, uint256 assets);

    /// @param _minter The minter contract address (can be zero for fixed price mode)
    /// @param _underlying The underlying token address (WSGETH for ERC4626 mode, VETH2 for fixed price mode)
    /// @param _epochLength The delay period in blocks before withdrawal is allowed
    /// @param _virtualPrice The virtual price for fixed price mode (1e18 = 1:1). Set to 0 for ERC4626 mode
    constructor(
        address _minter,
        address _underlying,
        uint256 _epochLength,
        uint256 _virtualPrice
    ) FIFOQueue(_epochLength) {
        if (_underlying == address(0)) {
            revert Errors.ZeroAddress();
        }
        // For ERC4626 mode, minter must be non-zero. For fixed price mode, minter can be zero
        if (_virtualPrice == 0 && _minter == address(0)) {
            revert Errors.ZeroAddress();
        }

        MINTER = _minter;
        UNDERLYING = _underlying;
        VIRTUAL_PRICE = _virtualPrice;

        uint256 maxUint256 = 2 ** 256 - 1;

        // Only approve minter if using ERC4626 mode
        if (_virtualPrice == 0 && _minter != address(0)) {
            IERC20(UNDERLYING).approve(_minter, maxUint256);
        }

        _grantRole(GOV, msg.sender);
    }

    /// @notice Requests a redemption of vault assets for the caller.
    /// @dev This function uses msg.sender as both the requester and owner. Only allowed when the contract is not paused.
    /// @param shares The number of shares to redeem.
    /// @return requestId The unique ID assigned to this redemption request.
    function requestRedeem(
        uint256 shares
    ) external nonReentrant whenNotPaused(uint16(1)) returns (uint256 requestId) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }
        address requester = msg.sender;
        address owner = msg.sender;

        IERC20(UNDERLYING).transferFrom(owner, address(this), shares);

        requestId = requestsCreated++;
        requests[requestId] = Request({requester: requester, shares: shares});
        uint256 assets = _convertSharesToAssets(shares);

        _stakeForWithdrawal(requester, assets);
        totalPendingRequest += assets;
        redeemRequests[requester] += assets;

        emit RedeemRequest(requester, owner, requestId, msg.sender, assets);
    }

    /// @notice Requests a redemption of vault assets on behalf of another user.
    /// @dev This function must be called by either the owner or an operator of the vault, and is only allowed when the contract is not paused.
    /// @param shares The number of shares to redeem.
    /// @param requester The address requesting the redemption (will receive the redemption).
    /// @param owner The owner of the vault tokens being redeemed from.
    /// @return requestId The unique ID assigned to this redemption request.
    function requestRedeemFor(
        uint256 shares,
        address requester,
        address owner
    ) external onlyOwnerOrOperator(owner) nonReentrant whenNotPaused(uint16(1)) returns (uint256 requestId) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }
        if (requester == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (owner == address(0)) {
            revert Errors.ZeroAddress();
        }

        IERC20(UNDERLYING).transferFrom(owner, address(this), shares);

        requestId = requestsCreated++;
        requests[requestId] = Request({requester: requester, shares: shares});
        uint256 assets = _convertSharesToAssets(shares);

        _stakeForWithdrawal(requester, assets);
        totalPendingRequest += assets;
        redeemRequests[requester] += assets;

        emit RedeemRequest(requester, owner, requestId, msg.sender, assets);
    }

    /// @notice Allows a user to redeem their vault shares.
    /// @dev This function uses msg.sender as the requester. Only allowed when the contract is not paused.
    /// @dev The function checks if the epoch has elapsed and if sufficient funds are available before processing the redemption.
    /// @param shares The number of shares to redeem.
    /// @param receiver The address that will receive the redeemed assets. Must not be zero address.
    /// @return assets The amount of assets that were successfully redeemed.
    function redeem(
        uint256 shares,
        address receiver
    ) external nonReentrant whenNotPaused(uint16(2)) returns (uint256 assets) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        address requester = msg.sender;
        assets = _convertSharesToAssets(shares);

        // Verify that the requester has sufficient claimable redemption request and epoch has elapsed
        uint256 claimable = claimableRedeemRequest(requester);
        if (claimable < assets) {
            // If not claimable, check if epoch has elapsed and sufficient balance exists
            _checkWithdraw(requester, totalBalance(), assets);
            // If check passes but claimable is still insufficient, revert
            // This can happen if balance is insufficient even after epoch elapsed
            if (totalBalance() < assets) {
                revert Errors.InsufficientBalance();
            }
        }

        _withdraw(requester, assets);
        redeemRequests[requester] -= assets;
        totalPendingRequest -= assets;
        totalAssetsOut += assets;
        requestsFulfilled++;

        if (VIRTUAL_PRICE == 0) {
            // ERC4626 mode: use minter to unstake and withdraw
            uint256 minterBalance = MINTER.balance;
            // This feels suboptimal, but is the easiest way to always burn the token on redemptions
            if (assets > minterBalance) {
                uint256 diff = assets - minterBalance;
                // We need to use donate/transfer etc. cant deposit and mint more shares as that messes up accouting
                payable(MINTER).transfer(diff);
            }

            // Always burn redeemed tokens
            SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
        } else {
            // Fixed price mode: direct ETH transfer
            if (assets > address(this).balance) {
                revert Errors.InsufficientBalance();
            }
            payable(receiver).transfer(assets);
        }

        emit Redeem(requester, receiver, shares, assets);
    }

    /// @notice Allows an operator to redeem vault shares on behalf of another user.
    /// @dev This function must be called by either the owner or an operator of the requester's vault, and is only allowed when the contract is not paused.
    /// @dev The function checks if the epoch has elapsed and if sufficient funds are available before processing the redemption.
    /// @param shares The number of shares to redeem.
    /// @param receiver The address that will receive the redeemed assets. Must not be zero address.
    /// @param requester The address requesting the redemption.
    /// @return assets The amount of assets that were successfully redeemed.
    function redeemFor(
        uint256 shares,
        address receiver,
        address requester
    ) external onlyOwnerOrOperator(requester) nonReentrant whenNotPaused(uint16(2)) returns (uint256 assets) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (requester == address(0)) {
            revert Errors.ZeroAddress();
        }

        assets = _convertSharesToAssets(shares);

        // Verify that the requester has sufficient claimable redemption request and epoch has elapsed
        uint256 claimable = claimableRedeemRequest(requester);
        if (claimable < assets) {
            // If not claimable, check if epoch has elapsed and sufficient balance exists
            _checkWithdraw(requester, totalBalance(), assets);
            // If check passes but claimable is still insufficient, revert
            // This can happen if balance is insufficient even after epoch elapsed
            if (totalBalance() < assets) {
                revert Errors.InsufficientBalance();
            }
        }

        _withdraw(requester, assets);
        redeemRequests[requester] -= assets;
        totalPendingRequest -= assets;
        totalAssetsOut += assets;
        requestsFulfilled++;

        if (VIRTUAL_PRICE == 0) {
            // ERC4626 mode: use minter to unstake and withdraw
            uint256 minterBalance = MINTER.balance;
            // This feels suboptimal, but is the easiest way to always burn the token on redemptions
            if (assets > minterBalance) {
                uint256 diff = assets - minterBalance;
                // We need to use donate/transfer etc. cant deposit and mint more shares as that messes up accouting
                payable(MINTER).transfer(diff);
            }

            // Always burn redeemed tokens
            SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
        } else {
            // Fixed price mode: direct ETH transfer
            if (assets > address(this).balance) {
                revert Errors.InsufficientBalance();
            }
            payable(receiver).transfer(assets);
        }

        emit Redeem(requester, receiver, shares, assets);
    }

    /// @notice Cancel a redeem request and return funds to the caller. Can only be done after the epoch has expired.
    /// @dev This function uses msg.sender as the requester. Only allowed when the contract is not paused.
    /// @dev The shares are calculated from the pending redeem request amount (stored in assets).
    /// @param receiver The address that will receive the returned shares. Must not be zero address.
    /// @return assets The amount of assets that were canceled (converted from shares).
    function cancelRedeem(
        address receiver
    ) external nonReentrant whenNotPaused(uint16(3)) returns (uint256 assets) {
        address requester = msg.sender;
        assets = pendingRedeemRequest(requester);

        if (assets == 0) {
            revert Errors.InvalidAmount();
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }

        _verifyEpochHasElapsed(requester);

        // Convert assets back to shares using current exchange rate
        // Note: This uses the current exchange rate, which may differ from when the request was made
        uint256 shares = _convertAssetsToShares(assets);

        // Get the total shares we have in the contract
        uint256 contractShares = IERC20(UNDERLYING).balanceOf(address(this));
        // Ensure we don't try to transfer more shares than we have
        if (shares > contractShares) {
            // If we don't have enough shares, use what we have and adjust assets accordingly
            shares = contractShares;
            if (VIRTUAL_PRICE == 0) {
                assets = IERC4626(UNDERLYING).convertToAssets(shares);
            } else {
                assets = _convertSharesToAssets(shares);
            }
        }

        // Update accounting - subtract the actual assets being canceled
        redeemRequests[requester] -= assets;
        totalPendingRequest -= assets;
        _withdraw(requester, assets);
        IERC20(UNDERLYING).transfer(receiver, shares);

        emit CancelRedeem(requester, receiver, shares, assets);
    }

    /// @notice Cancel a redeem request and return funds on behalf of another user. Can only be done after the epoch has expired.
    /// @dev This function must be called by either the owner or an operator of the requester's vault, and is only allowed when the contract is not paused.
    /// @dev The shares are calculated from the pending redeem request amount (stored in assets).
    /// @param receiver The address that will receive the returned shares. Must not be zero address.
    /// @param requester The address requesting the cancellation.
    /// @return assets The amount of assets that were canceled (converted from shares).
    function cancelRedeemFor(
        address receiver,
        address requester
    ) external onlyOwnerOrOperator(requester) nonReentrant whenNotPaused(uint16(3)) returns (uint256 assets) {
        assets = pendingRedeemRequest(requester);

        if (assets == 0) {
            revert Errors.InvalidAmount();
        }
        if (receiver == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (requester == address(0)) {
            revert Errors.ZeroAddress();
        }

        _verifyEpochHasElapsed(requester);

        // Convert assets back to shares using current exchange rate
        // Note: This uses the current exchange rate, which may differ from when the request was made
        uint256 shares = _convertAssetsToShares(assets);

        // Get the total shares we have in the contract
        uint256 contractShares = IERC20(UNDERLYING).balanceOf(address(this));
        // Ensure we don't try to transfer more shares than we have
        if (shares > contractShares) {
            // If we don't have enough shares, use what we have and adjust assets accordingly
            shares = contractShares;
            if (VIRTUAL_PRICE == 0) {
                assets = IERC4626(UNDERLYING).convertToAssets(shares);
            } else {
                assets = _convertSharesToAssets(shares);
            }
        }

        // Update accounting - subtract the actual assets being canceled
        redeemRequests[requester] -= assets;
        totalPendingRequest -= assets;
        _withdraw(requester, assets);
        IERC20(UNDERLYING).transfer(receiver, shares);

        emit CancelRedeem(requester, receiver, shares, assets);
    }

    /// @notice Allows the contract owner (GOV role) to submit redemption requests on behalf of users.
    /// @dev This function bypasses operator checks and allows the owner to initiate redemptions for any user.
    /// @dev Useful for protocol-initiated redemptions, migrations, or emergency situations.
    /// @param shares The number of shares to redeem.
    /// @param requester The address requesting the redemption (will receive the redemption).
    /// @param owner The owner of the vault tokens being redeemed from.
    /// @return requestId The unique ID assigned to this redemption request.
    function requestRedeemForUser(
        uint256 shares,
        address requester,
        address owner
    ) external onlyRole(GOV) nonReentrant whenNotPaused(uint16(1)) returns (uint256 requestId) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }
        if (requester == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (owner == address(0)) {
            revert Errors.ZeroAddress();
        }
        
        IERC20(UNDERLYING).transferFrom(owner, address(this), shares);

        requestId = requestsCreated++;
        requests[requestId] = Request({requester: requester, shares: shares});
        uint256 assets = _convertSharesToAssets(shares);

        _stakeForWithdrawal(requester, assets);
        totalPendingRequest += assets;
        redeemRequests[requester] += assets;

        emit RedeemRequest(requester, owner, requestId, msg.sender, assets);
    }

    /// @notice Toggles the pause state of a specific function.
    /// @param func The function ID to toggle pause state for (1=requestRedeem, 2=redeem, 3=cancelRedeem).
    function togglePause(uint16 func) external onlyRole(GOV) {
        bool paused = paused[func];
        if (paused) {
            _unpause(func);
        } else {
            _pause(func);
        }
    }

    /// @notice Sets the epoch length (delay period) for withdrawals.
    /// @param value The new epoch length in blocks.
    function setEpochLength(uint256 value) external onlyRole(GOV) {
        _setEpochLength(value);
    }

    /// @notice Returns the pending redemption request amount for an owner.
    /// @dev This returns the total assets requested for redemption, not the number of shares.
    /// @param owner The address to check pending requests for.
    /// @return assets The amount of assets pending redemption (not shares).
    function pendingRedeemRequest(address owner) public view returns (uint256 assets) {
        return redeemRequests[owner];
    }

    /// @notice Returns the claimable redemption request amount for an owner.
    /// @dev This returns the amount of assets that can be redeemed now (epoch elapsed and sufficient balance).
    /// @param owner The address to check claimable requests for.
    /// @return assets The amount of assets that can be redeemed now (0 if not claimable).
    function claimableRedeemRequest(address owner) public view returns (uint256 assets) {
        if (redeemRequests[owner] > 0 && _isWithdrawalAllowed(owner, totalBalance(), redeemRequests[owner])) {
            return redeemRequests[owner];
        } else {
            return 0;
        }
    }

    /// @notice Returns the total balance available for redemptions.
    /// @dev This includes both the contract's balance and the minter's balance (if applicable).
    /// @return The total balance available for fulfilling redemption requests.
    function totalBalance() internal view returns (uint256) {
        if (VIRTUAL_PRICE == 0 && MINTER != address(0)) {
            return address(this).balance + MINTER.balance;
        } else {
            return address(this).balance;
        }
    }

    /// @notice Converts shares to assets based on the configured mode.
    /// @dev Uses ERC4626 previewRedeem if virtualPrice is 0, otherwise uses fixed price calculation.
    /// @param shares The number of shares to convert.
    /// @return assets The equivalent amount of assets.
    function _convertSharesToAssets(uint256 shares) internal view returns (uint256 assets) {
        if (VIRTUAL_PRICE == 0) {
            // ERC4626 mode: use dynamic exchange rate
            return IERC4626(UNDERLYING).previewRedeem(shares);
        } else {
            // Fixed price mode: use virtual price
            return (shares * VIRTUAL_PRICE) / 1e18;
        }
    }

    /// @notice Converts assets to shares based on the configured mode.
    /// @dev Uses ERC4626 convertToShares if virtualPrice is 0, otherwise uses fixed price calculation.
    /// @param assets The amount of assets to convert.
    /// @return shares The equivalent number of shares.
    function _convertAssetsToShares(uint256 assets) internal view returns (uint256 shares) {
        if (VIRTUAL_PRICE == 0) {
            // ERC4626 mode: use dynamic exchange rate
            return IERC4626(UNDERLYING).convertToShares(assets);
        } else {
            // Fixed price mode: use virtual price
            return (assets * 1e18) / VIRTUAL_PRICE;
        }
    }

    receive() external payable {} // solhint-disable-line

    fallback() external payable {} // solhint-disable-line
}
