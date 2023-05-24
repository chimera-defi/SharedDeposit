// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;

import {VaultWithAdminFeeUpgradeable} from "../util/VaultWithAdminFeeUpgradeable.sol";
import {Eth2DepositHelperUpgradeable} from "../util/Eth2DepositHelperUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {IERC20MintableBurnable} from "../interfaces/IERC20MintableBurnable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

contract SharedDepositEth2 is VaultWithAdminFeeUpgradeable, Eth2DepositHelperUpgradeable {
    using SafeMathUpgradeable for uint256;

    /* ========== STATE VARIABLES ========== */

    function initialize(
        uint256 currentShares,
        uint256 adminFee,
        bool withdrawRefundDisabled,
        address _BETHTokenAddress
    ) public initializer {
        // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token
        uint256 cap = uint256(32).mul(1000).mul(1e18);
        uint256 buffer = uint256(10).mul(1e18); // roughly equal to 10 eth.
        uint256 costPerShare = uint256(1e18);
        uint256 epochLength = 1 weeks;
        __SharedDeposit_init(
            cap,
            buffer,
            currentShares,
            costPerShare,
            adminFee,
            withdrawRefundDisabled,
            _BETHTokenAddress,
            epochLength
        );
    }

    function __SharedDeposit_init(
        uint256 cap,
        uint256 buffer,
        uint256 currentShares,
        uint256 costPerShare,
        uint256 adminFee,
        bool withdrawRefundDisabled,
        address _BETHTokenAddress,
        uint256 epochLength
    ) internal initializer {
        __SharedDeposit_init_unchained(
            cap,
            buffer,
            currentShares,
            costPerShare,
            adminFee,
            withdrawRefundDisabled,
            _BETHTokenAddress,
            epochLength
        );
    }

    function __SharedDeposit_init_unchained(
        uint256 cap,
        uint256 buffer,
        uint256 currentShares,
        uint256 costPerShare,
        uint256 adminFee,
        bool withdrawRefundDisabled,
        address _BETHTokenAddress,
        uint256 epochLength
    ) internal initializer {
        __VaultWithAdminFeeUpgradeable_init(
            cap,
            buffer,
            currentShares,
            costPerShare,
            adminFee,
            withdrawRefundDisabled,
            _BETHTokenAddress,
            epochLength
        );
        __DepositHelper_init_unchained(mainnetDepositContractAddress);
    }

    function deposit() external payable nonReentrant whenNotPaused noContractAllowed {
        uint256 newShares = super._deposit(msg.value);
        super._mint(_msgSender(), newShares);
    }

    // TODO
    function stakeForWithdraw(uint256 amount) external nonReentrant whenNotPaused noContractAllowed {
        require(mintableBurnableToken.balanceOf(_msgSender()) >= amount, "Eth2Staker: Sender balance not enough");
        super._stakeForWithdrawal(_msgSender(), amount);
        super._burn(_msgSender(), amount);
    }

    function withdraw(uint256 amount) external nonReentrant whenNotPaused noContractAllowed {
        uint256 valToReturn = super._withdrawEth(amount);
        super._checkWithdraw(_msgSender(), address(this).balance, valToReturn, epochLength);

        address payable sender = payable(_msgSender());
        AddressUpgradeable.sendValue(sender, valToReturn);
    }

    function setValidatorsCreated(uint256 count) external onlyAdmin {
        validatorsCreated = count;
    }

    // This needs to be called once per validator
    function depositToEth2(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external onlyAdmin nonReentrant {
        super._depositToEth2(pubkey, withdrawal_credentials, signature, deposit_data_root);
    }

    /// @notice Submit index-matching arrays that form Phase 0 DepositData objects.
    ///         Will create a deposit transaction per index of the arrays submitted.
    ///
    /// @param pubkeys - An array of BLS12-381 public keys.
    /// @param withdrawal_credentials - An array of commitment to public key for withdrawals.
    /// @param signatures - An array of BLS12-381 signatures.
    /// @param deposit_data_roots - An array of the SHA-256 hash of the SSZ-encoded DepositData object.
    function batchDeposit(
        bytes[] calldata pubkeys,
        bytes[] calldata withdrawal_credentials,
        bytes[] calldata signatures,
        bytes32[] calldata deposit_data_roots
    ) external onlyAdmin nonReentrant {
        super._batchDeposit(pubkeys, withdrawal_credentials, signatures, deposit_data_roots);
    }

    function deductExitFee(uint256 amount) public view returns (uint256) {
        // Look at saddle and pick a higher number backstopped by a min
        uint256 min = 10000; // 1%
        uint256 max = 100000; // 10% - fetch from saddle
        uint256 pick = max;
        if (pick < min) {
            pick = min;
        }
        uint256 fee = super.getFeeGivenAmountAndAdminPrct(amount, pick);
        return fee;
    }
}
