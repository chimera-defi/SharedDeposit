// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Errors} from "../lib/Errors.sol";

contract FeeCalc is Ownable2Step {
    struct Settings {
        uint256 adminFee;
        uint256 exitFee;
        bool refundFeesOnWithdraw;
        bool chargeOnDeposit;
        bool chargeOnExit;
    }
    Settings public config;
    uint256 public adminFee;
    uint256 public costPerValidator;

    uint256 private immutable BIPS = 10000;
    
    error FeeTooHigh();
    
    constructor(Settings memory _settings) Ownable2Step() {
        // admin fee in bips (10000 = 100%)
        if (_settings.adminFee > BIPS) revert FeeTooHigh();
        if (_settings.exitFee > BIPS) revert FeeTooHigh();
        adminFee = _settings.adminFee;
        config = _settings;
        costPerValidator = ((32 + (32 * adminFee)) * 1 ether) / BIPS;
    }

    /// @notice Updates all fee settings
    /// @param newSettings New settings struct containing all fee configuration
    function set(Settings calldata newSettings) external onlyOwner {
        if (newSettings.adminFee > BIPS) revert FeeTooHigh();
        if (newSettings.exitFee > BIPS) revert FeeTooHigh();
        config = newSettings;
        adminFee = newSettings.adminFee;
    }

    /// @notice Sets whether fees should be refunded on withdrawal
    /// @param _refundFeesOnWithdraw True to refund fees on withdrawal, false otherwise
    function setRefundFeesOnWithdraw(bool _refundFeesOnWithdraw) external onlyOwner {
        config.refundFeesOnWithdraw = _refundFeesOnWithdraw;
    }

    /// @notice Sets the exit fee percentage
    /// @param _exitFee Exit fee in basis points (10000 = 100%)
    function setExitFee(uint256 _exitFee) external onlyOwner {
        if (_exitFee > BIPS) revert FeeTooHigh();
        config.exitFee = _exitFee;
    }

    /// @notice Sets the admin fee percentage
    /// @param amount Admin fee in basis points (10000 = 100%)
    function setAdminFee(uint256 amount) external onlyOwner {
        if (amount > BIPS) revert FeeTooHigh();
        adminFee = amount;
        config.adminFee = amount;
    }

    /// @notice Calculates deposit amount and fee after processing
    /// @param value The deposit amount in wei
    /// @param _sender The address making the deposit (currently unused, reserved for future fee reduction logic)
    /// @return amt The amount to mint after fees
    /// @return fee The fee amount deducted
    function processDeposit(uint256 value, address _sender) external view returns (uint256 amt, uint256 fee) {
        // TODO: _sender is currently unused but can be used later to calculate a fee reduction based on token holdings
        if (config.chargeOnDeposit) {
            fee = (value * adminFee) / BIPS;
            amt = value - fee;
        } else {
            // CRITICAL FIX: Initialize return values when no fee is charged
            fee = 0;
            amt = value;
        }
    }

    /// @notice Calculates withdrawal amount and fee after processing
    /// @param value The withdrawal amount in wei
    /// @param _sender The address making the withdrawal (currently unused, reserved for future fee reduction logic)
    /// @return amt The amount to return after fees
    /// @return fee The fee amount (positive if refunding, negative if charging)
    function processWithdraw(uint256 value, address _sender) external view returns (uint256 amt, uint256 fee) {
        // TODO: _sender is currently unused but can be used later to calculate a fee reduction based on token holdings
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
}
