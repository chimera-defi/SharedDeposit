pragma solidity 0.8.20;

/// @title  A contract for holding a eth2 validator withrawal pubkey
/// @author @chimeraDefi
/// @notice A contract for holding a eth2 validator withrawal pubkey
/// @dev Downstream contract needs to implement who can set the withdrawal address and set it
contract ETH2DepositWithdrawalCredentials {
    event WithdrawalCredentialSet(bytes _withdrawalCredential);

    bytes curr_withdrawal_pubkey; // Pubkey for ETH 2.0 withdrawal creds

    constructor() {}
    /// @notice sets curr_withdrawal_pubkey to be used when deploying validators
    function _setWithdrawalCredential(bytes memory _new_withdrawal_pubkey) internal {
        curr_withdrawal_pubkey = _new_withdrawal_pubkey;

        emit WithdrawalCredentialSet(_new_withdrawal_pubkey);
    }
}
