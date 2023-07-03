pragma solidity 0.8.20;

import {IDepositContract} from "../interfaces/IDepositContract.sol";
/// @title  A contract for holding a eth2 validator withrawal pubkey
/// @author @chimeraDefi
/// @notice A contract for holding a eth2 validator withrawal pubkey
/// @dev Downstream contract needs to implement who can set the withdrawal address and set it
contract ETH2DepositWithdrawalCredentials {
    uint256 internal constant _depositAmount = 32 ether;
    IDepositContract internal constant depositContract =  IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa); // solhint-disable-line
    bytes public curr_withdrawal_pubkey; // Pubkey for ETH 2.0 withdrawal creds

    event WithdrawalCredentialSet(bytes _withdrawalCredential);

    constructor() {} // solhint-disable-line

    /// @notice A more streamlined variant of batch deposit for use with preset withdrawal addresses
    ///         Submit index-matching arrays that form Phase 0 DepositData objects.
    ///         Will create a deposit transaction per index of the arrays submitted.
    ///
    /// @param pubkeys - An array of BLS12-381 public keys.
    /// @param signatures - An array of BLS12-381 signatures.
    /// @param depositDataRoots - An array of the SHA-256 hash of the SSZ-encoded DepositData object.
    function _batchDeposit(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) internal {
        uint256 loops = pubkeys.length;
        bytes memory wpk = curr_withdrawal_pubkey;

        // Loop through DepositData arrays submitting deposits
        for (uint256 i = 0; i < loops; i++) {
            depositContract.deposit{value: _depositAmount}(
                pubkeys[i],
                wpk,
                signatures[i],
                depositDataRoots[i]
            );
        }
    }

    /// @notice sets curr_withdrawal_pubkey to be used when deploying validators
    function _setWithdrawalCredential(bytes memory _new_withdrawal_pubkey) internal {
        curr_withdrawal_pubkey = _new_withdrawal_pubkey;

        emit WithdrawalCredentialSet(_new_withdrawal_pubkey);
    }
}
