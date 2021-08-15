// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract WithdrawQueueUpgradeable is Initializable {
    using SafeMathUpgradeable for uint256;
    struct UserEntry {
        uint256 amount;
        uint256 timestamp;
    }
    mapping(address => UserEntry) public userEntries;
    uint256 public epochLength;

    // if you just use the foll func you open yourself up to attacks
    // remember to move funds from the user
    // Based on:
    /*
     * Xdai easy staking deployed at
     * https://etherscan.io/address/0xecdaa01647290e1e9fdc8a26628a33561ba02949#code
     */
    function _checkWithdraw(
        address sender,
        uint256 balanceOfSelf,
        uint256 amountToWithdraw,
        uint256 _epochLength
    ) internal view returns (bool withdrawalAllowed) {
        UserEntry memory userEntry = userEntries[sender];
        require(amountToWithdraw >= balanceOfSelf, "WithdrawQueue: Not enough funds");
        require(userEntry.amount >= amountToWithdraw, "WithdrawQueue: Amount mismatch!");

        uint256 requestDate = userEntry.timestamp;
        uint256 timestamp = block.timestamp;
        uint256 lockEnd = requestDate.add(_epochLength);
        require(timestamp >= lockEnd, "WithdrawQueue: Too soon!");
        return true;
    }

    // Init
    function __WithdrawQueue_init(uint256 len) internal initializer {
        __WithdrawQueue_init_unchained(len);
    }

    function __WithdrawQueue_init_unchained(uint256 len) internal initializer {
        _setEpochLength(len);
    }

    // should be admin only or used in a constructor upstream
    function _setEpochLength(uint256 _value) internal {
        require(_value <= 30 days, "WithdrawQueue: epoch > 30");
        if (epochLength != _value) {
            epochLength = _value;
        }
    }

    function _stakeForWithdrawal(address sender, uint256 amount) internal {
        if (userEntries[sender].amount >= 0) {
            amount = userEntries[sender].amount.add(amount);
        }
        userEntries[sender] = UserEntry(amount, block.timestamp);
    }
}