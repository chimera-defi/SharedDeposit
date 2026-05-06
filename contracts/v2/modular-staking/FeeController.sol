// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Errors} from "../lib/Errors.sol";

/// @title FeeController - protocol fee configuration and accounting
/// @notice Stores fee rate and recipients; called by StakingCore when beacon rewards are reported.
///         Fees are distributed as minted shares (not ETH), so recipients earn from the reward pool
///         without requiring an ETH transfer on every oracle report.
/// @dev Fee is expressed in basis points (1 bp = 0.01%). Max 2000 bp (20%).
contract FeeController is AccessControl {
    bytes32 public constant GOV = keccak256("GOV");

    uint16 public constant MAX_FEE_BPS = 2000; // 20% ceiling

    uint16 public feeBps; // total protocol fee in basis points
    uint16 public treasurySplitBps; // what fraction of feeBps goes to treasury (rest to operator)

    address public treasury;
    address public operator;

    event FeeSet(uint16 feeBps, uint16 treasurySplitBps);
    event RecipientsSet(address treasury, address operator);
    event FeesDistributed(address indexed treasury, uint256 treasuryAmount, address indexed operator, uint256 operatorAmount);

    error FeeTooHigh();

    constructor(address gov, address _treasury, address _operator, uint16 _feeBps, uint16 _treasurySplitBps) {
        if (gov == address(0) || _treasury == address(0) || _operator == address(0)) revert Errors.ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);

        treasury = _treasury;
        operator = _operator;
        feeBps = _feeBps;
        treasurySplitBps = _treasurySplitBps;

        emit RecipientsSet(_treasury, _operator);
        emit FeeSet(_feeBps, _treasurySplitBps);
    }

    // ── Config ────────────────────────────────────────────────────────────────

    function setFee(uint16 _feeBps, uint16 _treasurySplitBps) external onlyRole(GOV) {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        feeBps = _feeBps;
        treasurySplitBps = _treasurySplitBps;
        emit FeeSet(_feeBps, _treasurySplitBps);
    }

    function setRecipients(address _treasury, address _operator) external onlyRole(GOV) {
        if (_treasury == address(0) || _operator == address(0)) revert Errors.ZeroAddress();
        treasury = _treasury;
        operator = _operator;
        emit RecipientsSet(_treasury, _operator);
    }

    // ── Query ─────────────────────────────────────────────────────────────────

    /// @notice Compute how many ETH-worth of fee shares to mint given `rewards` ETH.
    ///         Returns (treasuryAmount, operatorAmount) in wei.
    ///         Caller (StakingCore) then mints corresponding shares to treasury/operator.
    function computeFees(uint256 rewards)
        external
        view
        returns (uint256 treasuryAmount, uint256 operatorAmount)
    {
        uint256 totalFee = (rewards * feeBps) / 10000;
        treasuryAmount = (totalFee * treasurySplitBps) / 10000;
        operatorAmount = totalFee - treasuryAmount;
    }

    /// @notice Convenience getter for StakingCore to retrieve config in one call.
    function getFeeConfig()
        external
        view
        returns (uint16 _feeBps, uint16 _treasurySplitBps, address _treasury, address _operator)
    {
        return (feeBps, treasurySplitBps, treasury, operator);
    }

    /// @notice Emit distribution event (called by StakingCore after it mints the shares).
    function recordDistribution(uint256 treasuryAmount, uint256 operatorAmount) external onlyRole(GOV) {
        emit FeesDistributed(treasury, treasuryAmount, operator, operatorAmount);
    }
}
