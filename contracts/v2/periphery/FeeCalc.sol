// SPDX-License-Identifier: UNLICENSED
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

pragma solidity 0.8.20;

contract FeeCalc {
    using SafeMath for uint256;
    uint256 public adminFee;
    uint256 public costPerValidator;
    bool public refundFeesOnWithdraw;
    uint256 public exitFee;

    constructor(uint256 _adminFee, uint256 _exitFee) {
        adminFee = _adminFee;
        exitFee = _exitFee;
        costPerValidator = uint256(32).mul(1e18).add(adminFee);
    }

    function processDeposit(uint256 value, address _who) external view returns (uint256 amt, uint256 fee) {
        fee = value.mul(adminFee).div(costPerValidator);
        amt = value.sub(fee);
    }

    function processWithdraw(uint256 value, address _who) external view returns (uint256 amt, uint256 fee) {
        if (refundFeesOnWithdraw) {
            amt = value.mul(1e18).div(uint256(1).mul(1e18).sub(adminFee.mul(1e18).div(costPerValidator)));
            fee = amt.sub(value);
        } else {
            fee = value.mul(exitFee).div(costPerValidator);
            amt = value.sub(fee);
        }
    }

    function setAdminFee(uint256 amount) external {
        adminFee = amount;
        costPerValidator = uint256(32).mul(1e18).add(adminFee);
    }
}
