// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {FIFOQueue} from "../lib/FIFOQueue.sol";
import {Errors} from "../lib/Errors.sol";
import {OperatorSettable} from "../lib/OperatorSettable.sol";

import {SharedDepositMinterV2} from "./SharedDepositMinterV2.sol";

/**
 * @title WithdrawalQueue
 * @author @ChimeraDefi - chimera_defi@protonmail.com | sharedstake.org
 * @dev -
 * ERC-7540 inspired withdrawal contract
 * This contract is designed to be used with SharedDepositMinterV2 contract
 * As a module extension that adds 7540 methods requestRedeem and redeem
 * Example flow ->
 * user calls requestRedeem(user, user, userShares)
 * user calls setOperator(admin OR protocol provided keeper, true)
 * admin can now call redeem on the users behalf if needed after epoch
 * user calls redeem(user, user, userShares) after waiting for epoch
 * Caveats:
 * If the user requests another redemption, before fulfillment,
 * this resets the epoch length clock for their request
 */
contract WithdrawalQueue is AccessControl, Pausable, ReentrancyGuard, FIFOQueue, OperatorSettable {
    struct Request {
        address requester;
        uint256 shares;
    }
    // SharedDepositMinterV2 public immutable MINTER;
    address public immutable MINTER;
    address public immutable WSGETH;

    uint256 internal totalPendingRequest;
    uint256 internal requestsPending;
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

    constructor(address _minter, address _wsgEth, uint256 _epochLength) FIFOQueue(_epochLength) {
        MINTER = _minter;
        WSGETH = _wsgEth;

        uint256 maxUint256 = 2 ** 256 - 1;

        IERC20(WSGETH).approve(_minter, maxUint256);

        _grantRole(GOV, msg.sender);
    }

    function requestRedeem(
        uint256 shares,
        address requester,
        address owner
    ) external onlyOwnerOrOperator(owner) nonReentrant whenNotPaused returns (uint256 requestId) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }
        IERC20(WSGETH).transferFrom(owner, address(this), shares); // asset here is the Vault underlying asset

        requestId = requestsPending++;
        requests[requestId] = Request({requester: requester, shares: shares});

        _stakeForWithdrawal(owner, IERC4626(WSGETH).previewRedeem(shares));
        totalPendingRequest += shares;
        redeemRequests[requester] += shares; // underflow would revert if not enough claimable shares

        emit RedeemRequest(requester, owner, requestId, msg.sender, shares);
        return requestId;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address requester
    ) external onlyOwnerOrOperator(requester) nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }

        assets = IERC4626(WSGETH).previewRedeem(shares);

        if (claimableRedeemRequest(requester) < assets) {
            revert Errors.InvalidAmount();
        }
        _withdraw(requester, assets);

        // Treat everything as claimableRedeemRequest and validate here if there's adequate funds
        redeemRequests[requester] -= shares; // underflow would revert if not enough claimable shares
        totalPendingRequest -= shares;

        uint256 queueBalance = address(this).balance;
        uint256 minterBalance = MINTER.balance;

        if (queueBalance + minterBalance < assets) {
            revert Errors.InsufficientBalance();
        }

        // Track total returned
        totalAssetsOut += assets;
        requestsFulfilled++;
        // This feels suboptimal, but is the easiest way to always burn the token on redemptions
        if (assets > minterBalance) {
            uint256 diff = assets - minterBalance;
            // We need to use donate/transfer etc. cant deposit and mint more shares as that messes up accouting
            SharedDepositMinterV2(payable(MINTER)).deposit{value: diff}();
        }

        // Always burn redeemed tokens
        SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);

        emit Redeem(requester, receiver, shares, assets);
    }

    function togglePause() external onlyRole(GOV) {
        bool paused = paused();
        if (paused) {
            _unpause();
        } else {
            _pause();
        }
    }

    function pendingRedeemRequest(address owner) public view returns (uint256 shares) {
        return redeemRequests[owner];
    }

    // claimableRedeemRequest - returns owners shares in claimable state, i.e. epoch has elapsed and sufficient funds exist
    function claimableRedeemRequest(address owner) public view returns (uint256 shares) {
        uint256 totalBalance = address(this).balance + address(MINTER).balance;

        if (redeemRequests[owner] > 0 && _isWithdrawalAllowed(owner, totalBalance, redeemRequests[owner])) {
            return redeemRequests[owner];
        } else {
            return 0;
        }
    }

    receive() external payable {} // solhint-disable-line

    fallback() external payable {} // solhint-disable-line
}
