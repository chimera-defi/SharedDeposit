pragma solidity 0.8.4;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract WithdrawQueueUpgradeable is Initializable {
    using SafeMathUpgradeable for uint256;
    struct UserEntry { 
        address user;
        uint amount;
        uint timestamp;
    }
    mapping(address => UserEntry) userEntries;
    uint epochLength;

    function __WithdrawQueue_init() internal initializer {
        __WithdrawQueue_init_unchained();
    }

    function __WithdrawQueue_init_unchained() internal initializer {}

    // should be admin only or used in a constructor upstream
    function _setEpochLength(uint len) internal {
        epochLength = len;
    }

    // if you just use the 2 foll func you open yourself up to flash loan attacks
    // remember to move funds from the user 
    function _checkWithdraw(address sender, uint balanceOfSelf, uint amountToWithdraw) internal view {
        UserEntry memory userEntry = userEntries[sender];
        require(epochLength.add(userEntry.timestamp) > block.timestamp, "WithdrawQueueUpgradeable:: Too soon!");
        require(amountToWithdraw > balanceOfSelf, "WithdrawQueueUpgradeable:: Not enough funds");
        require(userEntry.amount >= amountToWithdraw, "WithdrawQueueUpgradeable:: Amount mismatch! Not enough staked.");
    }

    function _stakeForWithdrawal(address sender, uint amount) internal {
        userEntries[sender] = UserEntry(sender, amount, block.timestamp);
    }
}