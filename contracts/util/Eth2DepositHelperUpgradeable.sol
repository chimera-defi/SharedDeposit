// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {IDepositContract} from "../interfaces/IDepositContract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract Eth2DepositHelperUpgradeable is Initializable {
    using SafeMathUpgradeable for uint256;

    // The number of times the deposit to eth2 contract has been called to create validators
    uint256 public validatorsCreated; //initialized to 0
    uint256 public constant depositAmount = 32 ether;
    address public constant mainnetDepositContractAddress = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
    IDepositContract public depositContract;

    function __DepositHelper_init(address _depositContractAddress) internal initializer {
        __DepositHelper_init_unchained(_depositContractAddress);
    }

    function __DepositHelper_init_unchained(address _depositContractAddress) internal initializer {
        depositContract = IDepositContract(_depositContractAddress);
    }

    /// @notice Submit index-matching arrays that form Phase 0 DepositData objects.
    ///         Will create a deposit transaction per index of the arrays submitted.
    ///
    /// @param pubkeys - An array of BLS12-381 public keys.
    /// @param withdrawalCredentials - An array of commitment to public key for withdrawals.
    /// @param signatures - An array of BLS12-381 signatures.
    /// @param depositDataRoots - An array of the SHA-256 hash of the SSZ-encoded DepositData object.
    function _batchDeposit(
        bytes[] calldata pubkeys,
        bytes[] calldata withdrawalCredentials,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) internal {
        require(
            pubkeys.length == withdrawalCredentials.length &&
                pubkeys.length == signatures.length &&
                pubkeys.length == depositDataRoots.length,
            "DepositHelper::_batchDeposit: All fn param array's must be same length"
        );
        require(pubkeys.length > 0, "DepositHelper::_batchDeposit: Need >0 pubkeys");
        require(
            address(this).balance >= depositAmount.mul(pubkeys.length),
            "DepositHelper::_batchDeposit: Ether deposited must be >= 32 * (`pubkeys[]`.length)"
        );

        uint256 deposited;
        // Loop through DepositData arrays submitting deposits
        for (uint256 i = 0; i < pubkeys.length; i++) {
            depositContract.deposit{value: depositAmount}(
                pubkeys[i],
                withdrawalCredentials[i],
                signatures[i],
                depositDataRoots[i]
            );
            deposited = deposited.add(depositAmount);
        }
        assert(deposited == depositAmount.mul(pubkeys.length));
        validatorsCreated = validatorsCreated.add(pubkeys.length);
    }

    function _depositToEth2(
        bytes calldata pubkey,
        bytes calldata withdrawalCredential,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) internal {
        require(address(this).balance >= depositAmount, "Eth2Staker:_depositToEth2: Not enough balance"); //need at least 32 ETH

        validatorsCreated = validatorsCreated.add(1);

        depositContract.deposit{value: depositAmount}(pubkey, withdrawalCredential, signature, depositDataRoot);
    }

    function _setValidatorsCreated(uint256 count) internal {
        validatorsCreated = count;
    }

    uint256[50] private ______gap;
}
