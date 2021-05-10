pragma solidity 0.8.4;

import {IDepositContract} from "../interfaces/IDepositContract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract Eth2DepositHelperUpgradeable is Initializable {
    using SafeMathUpgradeable for uint256;

    // The number of times the deposit to eth2 contract has been called to create validators
    uint256 public validatorsCreated; //initialized to 0
    uint256 public constant depositAmount = 32 ether;
    address public constant mainnetDepositContractAddress =
        0x00000000219ab540356cBB839Cbe05303d7705Fa;

    IDepositContract private depositContract;

    function __DepositHelper_init() internal initializer {
        __DepositHelper_init_unchained();
    }

    function __DepositHelper_init_unchained() internal initializer {}

    /// @notice Submit index-matching arrays that form Phase 0 DepositData objects.
    ///         Will create a deposit transaction per index of the arrays submitted.
    ///
    /// @param pubkeys - An array of BLS12-381 public keys.
    /// @param withdrawal_credentials - An array of commitment to public key for withdrawals.
    /// @param signatures - An array of BLS12-381 signatures.
    /// @param deposit_data_roots - An array of the SHA-256 hash of the SSZ-encoded DepositData object.
    function _batchDeposit(
        bytes[] calldata pubkeys,
        bytes[] calldata withdrawal_credentials,
        bytes[] calldata signatures,
        bytes32[] calldata deposit_data_roots
    ) internal {
        require(
            pubkeys.length == withdrawal_credentials.length &&
            pubkeys.length == signatures.length &&
            pubkeys.length == deposit_data_roots.length,
            "#BatchDeposit batchDeposit(): All parameter array's must have the same length."
        );
        require(
            pubkeys.length > 0,
            "#BatchDeposit batchDeposit(): All parameter array's must have a length greater than zero."
        );
        require(
            address(this).balance >= depositAmount.mul(pubkeys.length),
            "#BatchDeposit batchDeposit(): Ether deposited needs to be at least: 32 * (parameter `pubkeys[]` length)."
        );
        
        uint256 deposited;
        // Loop through DepositData arrays submitting deposits
        for (uint256 i = 0; i < pubkeys.length; i++) {
            _depositToEth2(
                pubkeys[i],
                withdrawal_credentials[i],
                signatures[i],
                deposit_data_roots[i]
            );
            deposited = deposited.add(depositAmount);
        }
        assert(deposited == depositAmount.mul(pubkeys.length));
    }

    function _depositToEth2(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) internal {
        require(
            address(this).balance >= depositAmount,
            "Eth2Staker:depositToEth2: Not enough balance"
        ); //need at least 32 ETH

        validatorsCreated = validatorsCreated.add(1);

        depositContract.deposit{value: depositAmount}(
            pubkey,
            withdrawal_credentials,
            signature,
            deposit_data_root
        );
    }

    function _setValidatorsCreated(uint count) internal {
        validatorsCreated = count;
    }

    uint256[50] private ______gap;
}