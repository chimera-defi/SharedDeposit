// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IReportable} from "./interfaces/IReportable.sol";
import {Errors} from "../lib/Errors.sol";

/// @title OracleAdapter - beacon chain report ingestion with sanity gates
/// @notice Accepts signed reports from authorized submitters and forwards valid
///         ones to a target implementing IReportable. The target can be either
///         the legacy `StakingCore` or a `ValidatorModule` behind StakingRouter
///         — both expose `reportBeacon(uint256,uint256)` with identical semantics.
///
/// Safety rules enforced before forwarding:
///   1. Staleness   — report must arrive within `maxStalenessSeconds` of now.
///   2. Drift       — beacon balance change (per validator) must not exceed `maxDriftBps` bps.
///   3. Slash guard — balance cannot drop more than `maxSlashBps` bps per report.
///
/// @dev Multiple submitters are supported so oracle infra can be redundant.
///      A quorum mechanism (requiring M-of-N) is intentionally deferred to Phase 2.
contract OracleAdapter is AccessControl {
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GOV = keccak256("GOV");
    bytes32 public constant SUBMITTER = keccak256("SUBMITTER");

    // ── Config ────────────────────────────────────────────────────────────────
    IReportable public immutable REPORT_TARGET;

    uint256 public maxStalenessSeconds = 6 hours;
    uint256 public maxDriftBps = 1000;  // 10% per-validator balance change cap
    uint256 public maxSlashBps = 500;   // 5% total-balance slash cap per report

    // ── State ─────────────────────────────────────────────────────────────────
    uint256 public lastReportTime;
    uint256 public lastBeaconBalance;
    uint256 public lastBeaconValidators;

    // ── Events ────────────────────────────────────────────────────────────────
    event ReportSubmitted(
        address indexed submitter,
        uint256 beaconValidators,
        uint256 beaconBalance,
        uint256 timestamp
    );
    event ReportRejected(address indexed submitter, string reason);
    event MaxStalenessSet(uint256 seconds_);
    event MaxDriftSet(uint256 bps);
    event MaxSlashSet(uint256 bps);

    // ── Errors ────────────────────────────────────────────────────────────────
    error StaleReport(uint256 reportAge, uint256 maxAge);
    error BalanceDriftTooHigh(uint256 actual, uint256 max);
    error SlashTooLarge(uint256 actual, uint256 max);
    error FutureReportTimestamp(uint256 reportTimestamp, uint256 currentTimestamp);

    constructor(address reportTarget, address gov) {
        if (reportTarget == address(0) || gov == address(0)) revert Errors.ZeroAddress();
        REPORT_TARGET = IReportable(reportTarget);
        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);
    }

    // ── Report submission ─────────────────────────────────────────────────────

    /// @notice Submit a beacon chain report.
    ///         Reverts if any sanity check fails.
    /// @param beaconValidators  Number of active validators being reported.
    /// @param beaconBalance     Sum of validator balances in wei.
    /// @param reportTimestamp   Off-chain timestamp of the report (for staleness check).
    function submitReport(
        uint256 beaconValidators,
        uint256 beaconBalance,
        uint256 reportTimestamp
    ) external onlyRole(SUBMITTER) {
        // Reject reports from the future.
        if (reportTimestamp > block.timestamp) {
            revert FutureReportTimestamp(reportTimestamp, block.timestamp);
        }

        // 1. Staleness check.
        uint256 reportAge = block.timestamp > reportTimestamp ? block.timestamp - reportTimestamp : 0;
        if (reportAge > maxStalenessSeconds) {
            revert StaleReport(reportAge, maxStalenessSeconds);
        }

        // 2. Drift check: per-validator balance change must be within bounds.
        if (lastBeaconValidators > 0 && beaconValidators > 0) {
            uint256 prevAvg = lastBeaconBalance / lastBeaconValidators;
            uint256 newAvg = beaconBalance / beaconValidators;

            if (newAvg > prevAvg) {
                uint256 gainBps = ((newAvg - prevAvg) * 10000) / prevAvg;
                if (gainBps > maxDriftBps) revert BalanceDriftTooHigh(gainBps, maxDriftBps);
            }
        }

        // 3. Slash guard: total balance cannot fall by more than maxSlashBps.
        if (lastBeaconBalance > 0 && beaconBalance < lastBeaconBalance) {
            uint256 lossBps = ((lastBeaconBalance - beaconBalance) * 10000) / lastBeaconBalance;
            if (lossBps > maxSlashBps) revert SlashTooLarge(lossBps, maxSlashBps);
        }

        // All checks pass — update state and forward to StakingCore.
        lastBeaconBalance = beaconBalance;
        lastBeaconValidators = beaconValidators;
        lastReportTime = block.timestamp;

        REPORT_TARGET.reportBeacon(beaconValidators, beaconBalance);

        emit ReportSubmitted(msg.sender, beaconValidators, beaconBalance, reportTimestamp);
    }

    // ── Config (GOV only) ─────────────────────────────────────────────────────

    function setMaxStaleness(uint256 seconds_) external onlyRole(GOV) {
        maxStalenessSeconds = seconds_;
        emit MaxStalenessSet(seconds_);
    }

    function setMaxDriftBps(uint256 bps) external onlyRole(GOV) {
        maxDriftBps = bps;
        emit MaxDriftSet(bps);
    }

    function setMaxSlashBps(uint256 bps) external onlyRole(GOV) {
        maxSlashBps = bps;
        emit MaxSlashSet(bps);
    }

    function addSubmitter(address submitter) external onlyRole(GOV) {
        if (submitter == address(0)) revert Errors.ZeroAddress();
        grantRole(SUBMITTER, submitter);
    }

    function removeSubmitter(address submitter) external onlyRole(GOV) {
        revokeRole(SUBMITTER, submitter);
    }
}
