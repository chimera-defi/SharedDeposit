// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {StToken} from "./StToken.sol";
import {FeeController} from "./FeeController.sol";
import {ShareMath} from "./ShareMath.sol";
import {GranularPause} from "../lib/GranularPause.sol";
import {Errors} from "../lib/Errors.sol";

/// @title StakingCore - Lido-parity ETH staking vault
/// @notice Entry point for ETH deposits. Issues stToken shares to depositors.
///         Oracle (ORACLE role) reports beacon chain balance changes, triggering reward rebases.
///         Fee shares are minted to protocol recipients on each reward report.
///
/// Role model (principle of least privilege):
///   GOV          — governance (timelock/multisig): set fee controller, add/remove roles, unpause
///   ORACLE       — trusted report submitter (OracleAdapter contract)
///   GUARDIAN     — emergency pause (can act fast, no timelock needed)
///   NODE_OPERATOR— future: push ETH to validators (gated separately)
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
    event BeaconReported(uint256 beaconValidators, uint256 beaconBalance, uint256 totalPooledEther);
    event FeeSharesMinted(address indexed treasury, uint256 treasuryShares, address indexed operator, uint256 operatorShares);
    event FeeControllerSet(address indexed feeController);
    event BufferedEtherUpdated(uint256 bufferedEther);

    // ── Errors ────────────────────────────────────────────────────────────────
    error BeaconBalanceSanityFailed(uint256 reported, uint256 expected);

    constructor(address stToken, address gov) {
        if (stToken == address(0) || gov == address(0)) revert Errors.ZeroAddress();
        ST_TOKEN = StToken(stToken);
        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);
        _grantRole(GUARDIAN, gov);
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

    /// @notice Fallback: plain ETH transfer treated as a deposit with no referral.
    receive() external payable {
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
        // Sanity: beacon balance cannot be more than 2× the maximum honest value.
        if (_beaconValidators > 0) {
            uint256 maxPlausible = _beaconValidators * 32 ether * 2;
            if (newBeaconBalance > maxPlausible) {
                revert BeaconBalanceSanityFailed(newBeaconBalance, maxPlausible);
            }
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

    function _distributeFees(uint256 rewards, uint256 newTotalPooled) internal {
        (uint256 treasuryAmount, uint256 operatorAmount) = feeController.computeFees(rewards);
        if (treasuryAmount == 0 && operatorAmount == 0) return;

        uint256 totalFee = treasuryAmount + operatorAmount;
        uint256 newTotalShares = ST_TOKEN.getTotalShares();

        // Mint fee shares at the post-rebase exchange rate so fee recipients are
        // compensated exactly for their portion of the rewards.
        uint256 treasuryShares = ShareMath.getSharesByPooledEth(treasuryAmount, newTotalShares, newTotalPooled);
        uint256 operatorShares = ShareMath.getSharesByPooledEth(operatorAmount, newTotalShares, newTotalPooled);

        // Pool grows by the fee amount to back the newly issued shares.
        ST_TOKEN.setTotalPooledEther(newTotalPooled + totalFee);

        (, , address treasury, address operator) = feeController.getFeeConfig();

        if (treasuryShares > 0) ST_TOKEN.mintShares(treasury, treasuryShares);
        if (operatorShares > 0) ST_TOKEN.mintShares(operator, operatorShares);

        emit FeeSharesMinted(treasury, treasuryShares, operator, operatorShares);
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
