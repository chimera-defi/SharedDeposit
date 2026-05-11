// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Errors} from "../lib/Errors.sol";

/// @title FeeController - protocol fee configuration and accounting
/// @notice Stores fee rate and recipients; called by StakingCore when beacon rewards are reported.
///         Fees are distributed as minted shares (not ETH), so recipients earn from the reward pool
///         without requiring an ETH transfer on every oracle report.
///
///         Fee split model (all in basis points, sum <= 10000):
///           totalFee      = rewards * feeBps / 10000
///           treasury      = totalFee * treasurySplitBps / 10000
///           operator      = totalFee * operatorSplitBps / 10000
///           referralPool  = totalFee - treasury - operator (remainder)
/// @dev Fee is expressed in basis points (1 bp = 0.01%). Max 2000 bp (20%).
contract FeeController is AccessControl {
    bytes32 public constant GOV = keccak256("GOV");

    uint16 public constant MAX_FEE_BPS = 2000; // 20% ceiling

    uint16 public feeBps;           // total protocol fee in basis points
    uint16 public treasurySplitBps; // fraction of feeBps going to treasury
    uint16 public operatorSplitBps; // fraction of feeBps going to operator
    address public treasury;
    address public operator;
    address public referralRegistry; // ReferralRegistry contract for fee sharing

    event FeeSet(uint16 feeBps, uint16 treasurySplitBps, uint16 operatorSplitBps);
    event RecipientsSet(address treasury, address operator, address referralRegistry);
    event FeesDistributed(address indexed treasury, uint256 treasuryAmount, address indexed operator, uint256 operatorAmount, uint256 referralAmount);

    error FeeTooHigh();
    error SplitTooHigh();

    constructor(
        address gov,
        address _treasury,
        address _operator,
        address _referralRegistry,
        uint16 _feeBps,
        uint16 _treasurySplitBps,
        uint16 _operatorSplitBps
    ) {
        if (gov == address(0) || _treasury == address(0) || _operator == address(0)) revert Errors.ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        if (_treasurySplitBps + _operatorSplitBps > 10000) revert SplitTooHigh();

        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);

        treasury = _treasury;
        operator = _operator;
        referralRegistry = _referralRegistry;
        feeBps = _feeBps;
        treasurySplitBps = _treasurySplitBps;
        operatorSplitBps = _operatorSplitBps;

        emit RecipientsSet(_treasury, _operator, _referralRegistry);
        emit FeeSet(_feeBps, _treasurySplitBps, _operatorSplitBps);
    }

    // ── Config ────────────────────────────────────────────────────────────────

    function setFee(uint16 _feeBps, uint16 _treasurySplitBps, uint16 _operatorSplitBps) external onlyRole(GOV) {
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        if (_treasurySplitBps + _operatorSplitBps > 10000) revert SplitTooHigh();
        feeBps = _feeBps;
        treasurySplitBps = _treasurySplitBps;
        operatorSplitBps = _operatorSplitBps;
        emit FeeSet(_feeBps, _treasurySplitBps, _operatorSplitBps);
    }

    function setRecipients(address _treasury, address _operator, address _referralRegistry) external onlyRole(GOV) {
        if (_treasury == address(0) || _operator == address(0)) revert Errors.ZeroAddress();
        treasury = _treasury;
        operator = _operator;
        referralRegistry = _referralRegistry;
        emit RecipientsSet(_treasury, _operator, _referralRegistry);
    }

    // ── Query ─────────────────────────────────────────────────────────────────

    /// @notice Compute how many ETH-worth of fee shares to mint given `rewards` ETH.
    ///         Returns (treasuryAmount, operatorAmount, referralAmount) in wei.
    ///         Caller (StakingCore) then mints corresponding shares to treasury/operator.
    ///         Referral amount is sent to ReferralRegistry as shares.
    function computeFees(uint256 rewards)
        external
        view
        returns (uint256 treasuryAmount, uint256 operatorAmount, uint256 referralAmount)
    {
        uint256 totalFee = (rewards * feeBps) / 10000;
        treasuryAmount = (totalFee * treasurySplitBps) / 10000;
        operatorAmount = (totalFee * operatorSplitBps) / 10000;
        referralAmount = totalFee - treasuryAmount - operatorAmount;
    }

    /// @notice Convenience getter for StakingCore to retrieve config in one call.
    function getFeeConfig()
        external
        view
        returns (uint16 _feeBps, uint16 _treasurySplitBps, uint16 _operatorSplitBps, address _treasury, address _operator, address _referralRegistry)
    {
        return (feeBps, treasurySplitBps, operatorSplitBps, treasury, operator, referralRegistry);
    }

    /// @notice Convenience getter for fee recipients only.
    function getRecipients() external view returns (address _treasury, address _operator) {
        return (treasury, operator);
    }
}
