pragma solidity 0.8.20;

contract ETH2DepositWithdrawalCredentials {
    event WithdrawalCredentialSet(bytes _withdrawalCredential);

    bytes curr_withdrawal_pubkey; // Pubkey for ETH 2.0 withdrawal creds. If you change it, you must empty the validators array

    constructor() {}
    /// @notice Requires empty validator stack as changing withdrawal creds invalidates signature
    /// @dev May need to call clearValidatorArray() first
    function _setWithdrawalCredential(bytes memory _new_withdrawal_pubkey) internal {
        curr_withdrawal_pubkey = _new_withdrawal_pubkey;

        emit WithdrawalCredentialSet(_new_withdrawal_pubkey);
    }
}