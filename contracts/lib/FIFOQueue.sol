// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Errors} from "./Errors.sol";

// Simple First in first out queue
// Uses a system of cascading locks based on the block number. 
// Users need to wait a minimum of epochLength blocks before withdrawing
// Users past the epoch boundary can claim, allowing some time for earlier users to claim first
abstract contract FIFOQueue {
    struct UserEntry {
        uint256 amount;
        uint256 blocknum;
    }
    mapping(address => UserEntry) public userEntries;

    uint256 public epochLength;
    constructor(uint256 _epochLength) {
        epochLength =  _epochLength;
    }

    function _checkWithdraw(
        address sender,
        uint256 balanceOfSelf,
        uint256 amountToWithdraw
    ) public view returns (bool withdrawalAllowed) {
        UserEntry memory userEntry = userEntries[sender];
        if (amountToWithdraw > balanceOfSelf
            || userEntry.amount > amountToWithdraw) {
            revert Errors.InvalidAmount();
        }
       uint256 lockEnd = userEntry.blocknum + epochLength;

        if (block.number < lockEnd) {
            revert Errors.TooEarly();
        }
        return true;
    }

    // should be admin only or used in a constructor upstream
    // set epoch length in blocks
    function _setEpochLength(uint256 _value) internal {
        if(_value == 0) {
            revert Errors.InvalidAmount();
        }
        epochLength = _value;
    }

    function _stakeForWithdrawal(address sender, uint256 amount) internal {
        UserEntry memory ue = userEntries[sender];
        ue.amount = ue.amount + amount;
        ue.blocknum = block.number;
        userEntries[sender] = ue;
    }
}
