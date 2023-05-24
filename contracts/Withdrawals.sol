pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract Withdrawals {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserEntry {
        uint256 amount;
    }
    mapping(address => UserEntry) public userEntries;
    IERC20 public vEth2Token;

    uint256 public virtualPrice;
    uint256 public totalOut;

    constructor(address _underlying, uint256 _virtualPrice) {
        vEth2Token = IERC20(_underlying);
        virtualPrice = _virtualPrice;
    }

    function deposit(uint256 amount) external {
        address user = msg.sender;
        require(vEth2Token.balanceOf(user) >= amount, "SD:SBLA"); // Sender bal < Amount

        vEth2Token.transferFrom(user, address(this), amount);

        _stakeForWithdrawal(user, amount);
    }

    function withdraw() external {
        address user = msg.sender;
        uint256 amt = userEntries[user].amount;
        delete userEntries[user];

        vEth2Token.transferFrom(address(this), user, amt);
    }

    function redeem() external {
        _redeem(msg.sender, userEntries[msg.sender].amount);
    }

    function redeem(address user, uint256 amount) external {
        _redeem(user, amount);
    }

    function _redeem(address user, uint256 amount) internal {
        uint256 amountToReturn = _getAmountGivenShares(amount);
        require(address(this).balance >= amountToReturn, "SD:CBLA"); // Contract bal less than amount requested
        if (_checkWithdraw(user, amount)) {
            delete userEntries[user];
            address payable sender = payable(user);
            totalOut += amountToReturn;

            require(sender.send(amountToReturn), "Error refunding");
        }
    }

    function _getAmountGivenShares(uint256 shares) internal returns (uint256) {
        return shares.mul(virtualPrice).div(1e18);
    }

    function _stakeForWithdrawal(address sender, uint256 amount) internal {
        UserEntry memory ue = userEntries[sender];
        ue.amount = ue.amount.add(amount);
        userEntries[sender] = ue;
    }

    function _checkWithdraw(
        address sender,
        uint256 amountToWithdraw
    ) internal returns (bool withdrawalAllowed) {
        UserEntry memory userEntry = userEntries[sender];
        require(userEntry.amount >= amountToWithdraw, "WQ:AGC");
        return true;
    }
}
