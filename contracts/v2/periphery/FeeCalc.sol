// SPDX-License-Identifier: UNLICENSED
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

pragma solidity ^0.8.20;

contract FeeCalc is Ownable2Step {
    struct Settings {
        uint256 adminFee;
        uint256 exitFee;
        bool refundFeesOnWithdraw;
        bool chargeOnDeposit;
        bool chargeOnExit;
    }
    Settings private config;
    uint256 public adminFee;
    uint256 public costPerValidator;

    uint256 private immutable BIPS = 10000;
    constructor(Settings memory _settings) Ownable2Step() {
        // admin fee in bips (10000 = 100%)
        adminFee = _settings.adminFee;
        config = _settings;
        costPerValidator = ((32 + (32 * adminFee)) * 1 ether) / BIPS;
    }

    function processDeposit(uint256 value) external view returns (uint256 amt, uint256 fee) {
        if (config.chargeOnDeposit) {
            fee = (value * adminFee) / BIPS;
            amt = value - fee;
        }
    }

    function processWithdraw(uint256 value) external view returns (uint256 amt, uint256 fee) {
        if (config.refundFeesOnWithdraw) {
            fee = (value * adminFee) / BIPS;
            amt = value + fee;
        } else if (config.chargeOnExit) {
            fee = (value * config.exitFee) / BIPS;
            amt = value - fee;
        } else {
            fee = 0;
            amt = value;
        }
    }

    function set(Settings calldata newSettings) external onlyOwner {
        config = newSettings;
        adminFee = newSettings.adminFee;
    }

    function setRefundFeesOnWithdraw(bool _refundFeesOnWithdraw) external onlyOwner {
        config.refundFeesOnWithdraw = _refundFeesOnWithdraw;
    }

    function setExitFee(uint256 _exitFee) external onlyOwner {
        config.exitFee = _exitFee;
    }

    function setAdminFee(uint256 amount) external onlyOwner {
        adminFee = amount;
        config.adminFee = amount;
    }
}
