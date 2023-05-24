pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Withdrawals {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    error ContractBalanceTooLow();
    error UserStakeTooLow();

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
        // vEth2 transfer from returns true otherwise reverts
        if (vEth2Token.transferFrom(msg.sender, address(this), amount)) {
            _stakeForWithdrawal(msg.sender, amount);
        }
    }

    function exit() external {
        uint256 amt = userEntries[msg.sender].amount;
        delete userEntries[msg.sender];

        vEth2Token.transferFrom(address(this), msg.sender, amt);
    }

    function redeem() external {
        _redeem(msg.sender, userEntries[msg.sender].amount);
    }

    function redeem(address user, uint256 amount) external {
        _redeem(user, amount);
    }

    function _redeem(address user, uint256 amount) internal {
        uint256 amountToReturn = _getAmountGivenShares(amount);
        _check(user, amount, amountToReturn);
        delete userEntries[user];
        totalOut += amountToReturn;

        payable(user).transfer(amountToReturn);
    }

    function _getAmountGivenShares(uint256 shares) internal returns (uint256) {
        return shares.mul(virtualPrice).div(1e18);
    }

    function _stakeForWithdrawal(address sender, uint256 amount) internal {
        UserEntry memory ue = userEntries[sender];
        ue.amount = ue.amount.add(amount);
        userEntries[sender] = ue;
    }

    function _check(
        address sender,
        uint256 amountToWithdraw,
        uint256 amountToReturn
    ) internal {
        if (userEntries[sender].amount < amountToWithdraw) {
            revert UserStakeTooLow();
        }
        if (address(this).balance < amountToReturn) {
            revert ContractBalanceTooLow();
        }
    }
}
