// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {StToken} from "./StToken.sol";
import {FeeController} from "./FeeController.sol";
import {ShareMath} from "./ShareMath.sol";
import {IReferralRegistry} from "./interfaces/IReferralRegistry.sol";
import {GranularPause} from "../lib/GranularPause.sol";
import {Errors} from "../lib/Errors.sol";

/// @title StakingCore - SharedStake V2 ETH staking vault
/// @notice Entry point for ETH deposits. Issues stToken shares to depositors.
///         Oracle (ORACLE role) reports beacon chain balance changes, triggering reward rebases.
///         Fee shares are minted to protocol recipients on each reward report.
///
/// Role model (principle of least privilege):
///   GOV          — governance (timelock/multisig): set fee controller, add/remove roles, unpause
///   ORACLE       — trusted report submitter (OracleAdapter contract)
///   GUARDIAN     — emergency pause (can act fast, no timelock needed)
///   NODE_OPERATOR— moves buffered ETH into beacon baseline via notifyBeaconDeposit
contract StakingCore is AccessControl, ReentrancyGuard, GranularPause {
    using ShareMath for *;

    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GOV = keccak256("GOV");
    bytes32 public constant ORACLE = keccak256("ORACLE");
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");
    bytes32 public constant NODE_OPERATOR = keccak256("NODE_OPERATOR");

    // ── Pause IDs ─────────────────────────────────────────────────────────────
    uint16 public constant PAUSE_SUBMIT = 0;

    // ── Immutables ────────────────────────────────────────────────────────────
    StToken public immutable ST_TOKEN;

    // ── State ─────────────────────────────────────────────────────────────────
    FeeController public feeController;

    uint256 private _bufferedEther;   // ETH held in this contract (pending validator assignment)
    uint256 private _beaconBalance;   // last reported sum of all validator balances
    uint256 private _beaconValidators; // last reported validator count

    // ── Events ────────────────────────────────────────────────────────────────
    event Submitted(address indexed sender, uint256 ethAmount, address referral, uint256 sharesAmount);
    event SubmittedWithAttribution(
        address indexed sender,
        address indexed referral,
        bytes32 indexed sourceId,
        uint256 ethAmount,
        uint256 sharesAmount
    );
    event BeaconReported(uint256 beaconValidators, uint256 beaconBalance, uint256 totalPooledEther);
    event FeeSharesMinted(address indexed treasury, uint256 treasuryShares, address indexed operator, uint256 operatorShares);
    event FeeRoutingTelemetry(
        uint256 rewardsAmount,
        uint256 totalFeeAmount,
        address indexed treasury,
        uint256 treasuryAmount,
        uint256 treasuryShares,
        address indexed operator,
        uint256 operatorAmount,
        uint256 operatorShares
    );
    event FeeControllerSet(address indexed feeController);
    event BufferedEtherUpdated(uint256 bufferedEther);
    event BeaconDepositNotified(uint256 amount, uint256 bufferedEther, uint256 beaconBalance);

    // ── Errors ────────────────────────────────────────────────────────────────
    error BeaconBalanceSanityFailed(uint256 reported, uint256 expected);
    error BeaconBaselineNotInitialized(uint256 reportedBalance);
    error BeaconDepositExceedsBuffered(uint256 amount, uint256 bufferedEther);

    constructor(address stToken, address gov) {
        if (stToken == address(0) || gov == address(0)) revert Errors.ZeroAddress();
        ST_TOKEN = StToken(stToken);
        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);
        _grantRole(GUARDIAN, gov);
        _grantRole(NODE_OPERATOR, gov);
    }

    // ── Deposit ───────────────────────────────────────────────────────────────

    /// @notice Deposit ETH and receive stToken shares.
    /// @param referral Optional referral address for front-end attribution.
    /// @return sharesAmount Shares minted to msg.sender.
    function submit(address referral)
        external
        payable
        nonReentrant
        whenNotPaused(PAUSE_SUBMIT)
        returns (uint256 sharesAmount)
    {
        if (msg.value == 0) revert Errors.InvalidAmount();
        sharesAmount = _submit(msg.sender, msg.value, referral);
    }

    /// @notice Deposit ETH and receive stToken shares with source attribution metadata.
    /// @param referral Optional referral address for front-end attribution.
    /// @param sourceId Optional source identifier for indexer and analytics attribution.
    /// @return sharesAmount Shares minted to msg.sender.
    function submitWithAttribution(address referral, bytes32 sourceId)
        external
        payable
        nonReentrant
        whenNotPaused(PAUSE_SUBMIT)
        returns (uint256 sharesAmount)
    {
        if (msg.value == 0) revert Errors.InvalidAmount();
        sharesAmount = _submit(msg.sender, msg.value, referral);
        emit SubmittedWithAttribution(msg.sender, referral, sourceId, msg.value, sharesAmount);
    }

    /// @notice Fallback: plain ETH transfer treated as a deposit with no referral.
    receive() external payable nonReentrant whenNotPaused(PAUSE_SUBMIT) {
        if (msg.value == 0) revert Errors.InvalidAmount();
        _submit(msg.sender, msg.value, address(0));
    }

    function _submit(address sender, uint256 amount, address referral) internal returns (uint256 sharesAmount) {
        uint256 currentPooled = ST_TOKEN.totalPooledEther();
        uint256 currentShares = ST_TOKEN.getTotalShares();

        sharesAmount = ShareMath.getSharesByPooledEth(amount, currentShares, currentPooled);

        _bufferedEther += amount;
        // Pool grows by deposit amount before shares are issued (conservative: no dilution).
        ST_TOKEN.setTotalPooledEther(currentPooled + amount);
        ST_TOKEN.mintShares(sender, sharesAmount);
        _recordReferral(sender, referral, amount, sharesAmount);

        emit Submitted(sender, amount, referral, sharesAmount);
        emit BufferedEtherUpdated(_bufferedEther);
    }

    // ── Oracle reporting ──────────────────────────────────────────────────────

    /// @notice Called by OracleAdapter when a new beacon chain report is accepted.
    ///         Updates totalPooledEther and distributes fee shares on positive rewards.
    /// @param newBeaconValidators Number of validators being reported.
    /// @param newBeaconBalance    Sum of all validator balances (in wei).
    function reportBeacon(uint256 newBeaconValidators, uint256 newBeaconBalance)
        external
        onlyRole(ORACLE)
    {
        // Sanity: beacon balance cannot be more than 1.5× the maximum honest value.
        if (newBeaconValidators > 0) {
            uint256 maxPlausible = newBeaconValidators * 32 ether * 3 / 2;
            if (newBeaconBalance > maxPlausible) {
                revert BeaconBalanceSanityFailed(newBeaconBalance, maxPlausible);
            }
        }

        // Prevent principal from being counted as rewards on the first positive
        // report. NODE_OPERATOR must move buffered ETH into beacon baseline first.
        if (_beaconBalance == 0 && newBeaconBalance > 0) {
            revert BeaconBaselineNotInitialized(newBeaconBalance);
        }

        uint256 preTotalPooled = ST_TOKEN.totalPooledEther();

        _beaconValidators = newBeaconValidators;
        _beaconBalance = newBeaconBalance;

        uint256 postTotalPooled = _bufferedEther + newBeaconBalance;
        ST_TOKEN.setTotalPooledEther(postTotalPooled);

        // Distribute fee shares when there are positive rewards.
        if (postTotalPooled > preTotalPooled && address(feeController) != address(0)) {
            uint256 rewards = postTotalPooled - preTotalPooled;
            _distributeFees(rewards, postTotalPooled);
        }

        emit BeaconReported(newBeaconValidators, newBeaconBalance, postTotalPooled);
    }

    /// @notice Moves ETH accounting from buffered to beacon-side baseline.
    /// @dev Called by NODE_OPERATOR when validator deposits are broadcast.
    ///      Keeps total pooled ETH unchanged while initializing or growing the
    ///      beacon baseline used by oracle delta reports.
    function notifyBeaconDeposit(uint256 amount) external onlyRole(NODE_OPERATOR) {
        if (amount == 0) revert Errors.InvalidAmount();
        uint256 buffered = _bufferedEther;
        if (amount > buffered) revert BeaconDepositExceedsBuffered(amount, buffered);

        _bufferedEther = buffered - amount;
        _beaconBalance += amount;

        emit BeaconDepositNotified(amount, _bufferedEther, _beaconBalance);
        emit BufferedEtherUpdated(_bufferedEther);
    }

    function _distributeFees(uint256 rewards, uint256 newTotalPooled) internal {
        (, , , address treasury, address operator, address referralRegistry) = feeController.getFeeConfig();

        (uint256 treasuryAmount, uint256 operatorAmount, uint256 referralAmount) = feeController.computeFees(rewards);
        if (referralRegistry == address(0)) {
            referralAmount = 0;
        }
        if (treasuryAmount == 0 && operatorAmount == 0 && referralAmount == 0) return;

        uint256 totalFee = treasuryAmount + operatorAmount + referralAmount;
        uint256 newTotalShares = ST_TOKEN.getTotalShares();

        // Mint fee shares at the post-rebase exchange rate so fee recipients are
        // compensated exactly for their portion of the rewards.
        uint256 treasuryShares = ShareMath.getSharesByPooledEth(treasuryAmount, newTotalShares, newTotalPooled);
        uint256 operatorShares = ShareMath.getSharesByPooledEth(operatorAmount, newTotalShares, newTotalPooled);
        uint256 referralShares = ShareMath.getSharesByPooledEth(referralAmount, newTotalShares, newTotalPooled);

        // Keep pool accounting strictly tied to real backing (buffer + beacon).
        // Fee recipients are paid via share dilution from existing rewards.

        if (treasuryShares > 0) ST_TOKEN.mintShares(treasury, treasuryShares);
        if (operatorShares > 0) ST_TOKEN.mintShares(operator, operatorShares);
        if (referralRegistry != address(0) && referralShares > 0) {
            ST_TOKEN.mintShares(referralRegistry, referralShares);
            IReferralRegistry(referralRegistry).depositReferralFeeShares(referralShares);
        }

        emit FeeSharesMinted(treasury, treasuryShares, operator, operatorShares);
        emit FeeRoutingTelemetry(
            rewards,
            totalFee,
            treasury,
            treasuryAmount,
            treasuryShares,
            operator,
            operatorAmount,
            operatorShares
        );
    }

    function _recordReferral(address sender, address referral, uint256 amount, uint256 sharesAmount) internal {
        if (referral == address(0) || address(feeController) == address(0)) return;
        (, , , , , address referralRegistry) = feeController.getFeeConfig();
        if (referralRegistry == address(0)) return;
        IReferralRegistry(referralRegistry).recordDeposit(referral, sender, amount, sharesAmount);
    }

    // ── Admin ─────────────────────────────────────────────────────────────────

    function setFeeController(address fc) external onlyRole(GOV) {
        if (fc == address(0)) revert Errors.ZeroAddress();
        feeController = FeeController(fc);
        emit FeeControllerSet(fc);
    }

    function pause(uint16 fnId) external onlyRole(GUARDIAN) {
        _pause(fnId);
    }

    function unpause(uint16 fnId) external onlyRole(GOV) {
        _unpause(fnId);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    function totalPooledEther() external view returns (uint256) {
        return _bufferedEther + _beaconBalance;
    }

    function bufferedEther() external view returns (uint256) {
        return _bufferedEther;
    }

    function beaconBalance() external view returns (uint256) {
        return _beaconBalance;
    }

    function beaconValidators() external view returns (uint256) {
        return _beaconValidators;
    }
}
