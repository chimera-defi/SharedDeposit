// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {StToken} from "./StToken.sol";
import {ShareMath} from "./ShareMath.sol";
import {Errors} from "../lib/Errors.sol";

/// @title WithdrawalQueueV2 - Lido-parity withdrawal queue
/// @notice Three-step lifecycle:
///   1. requestWithdrawals  — user burns stToken shares, obtains requestId(s)
///   2. finalize            — guardian finalizes a batch, providing ETH at the agreed share rate
///   3. claimWithdrawal     — request owner withdraws their ETH
///
/// Invariants maintained:
///   - No request can claim more ETH than it contributed shares × finalized share rate.
///   - Once finalized, the ETH for a batch is locked and cannot be redirected.
///   - Claimed flag prevents replay.
///
/// Safety: the contract accepts ETH during finalize so it can hold funds between finalize and claim.
contract WithdrawalQueueV2 is AccessControl, ReentrancyGuard {
    using Address for address payable;

    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GOV = keccak256("GOV");
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");

    // ── Types ─────────────────────────────────────────────────────────────────
    struct WithdrawalRequest {
        address owner;
        uint256 stShares;          // shares burned at request time
        uint256 ethAmount;         // ETH owed — set during finalize
        bool finalized;
        bool claimed;
    }

    // ── State ─────────────────────────────────────────────────────────────────
    StToken public immutable ST_TOKEN;

    uint256 public nextRequestId = 1;
    uint256 public lastFinalizedRequestId; // inclusive upper bound of finalized range

    mapping(uint256 => WithdrawalRequest) public requests;

    // ETH locked for finalized-but-unclaimed requests.
    uint256 public lockedEther;

    // ── Limits ────────────────────────────────────────────────────────────────
    uint256 public constant MIN_WITHDRAWAL = 0.01 ether;
    uint256 public constant MAX_WITHDRAWAL = 1000 ether;

    // ── Events ────────────────────────────────────────────────────────────────
    event WithdrawalRequested(
        address indexed owner,
        uint256 indexed requestId,
        uint256 stShares,
        uint256 stTokenAmount
    );
    event BatchFinalized(uint256 indexed fromRequestId, uint256 indexed toRequestId, uint256 ethProvided);
    event WithdrawalClaimed(address indexed owner, address indexed recipient, uint256 indexed requestId, uint256 ethAmount);
    event WithdrawalCancelled(address indexed owner, uint256 indexed requestId, uint256 stShares);

    // ── Errors ────────────────────────────────────────────────────────────────
    error RequestNotFinalized(uint256 requestId);
    error RequestAlreadyClaimed(uint256 requestId);
    error NotRequestOwner(uint256 requestId, address caller);
    error AmountOutOfBounds(uint256 amount);
    error InsufficientFinalizeEth(uint256 required, uint256 provided);
    error InvalidRequestRange(uint256 from, uint256 to);

    constructor(address stToken, address gov) {
        if (stToken == address(0) || gov == address(0)) revert Errors.ZeroAddress();
        ST_TOKEN = StToken(stToken);
        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);
        _grantRole(GUARDIAN, gov);
    }

    // ── Request ───────────────────────────────────────────────────────────────

    /// @notice Burn stTokens and enqueue withdrawal requests.
    /// @param amounts  Array of stToken amounts to withdraw (each entry = one request).
    /// @param owner    Address that will own the requests and can claim ETH.
    /// @return requestIds Assigned request IDs.
    function requestWithdrawals(uint256[] calldata amounts, address owner)
        external
        nonReentrant
        returns (uint256[] memory requestIds)
    {
        if (owner == address(0)) revert Errors.ZeroAddress();

        requestIds = new uint256[](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            requestIds[i] = _enqueueRequest(amounts[i], owner);
        }
    }

    function _enqueueRequest(uint256 stTokenAmount, address owner) internal returns (uint256 requestId) {
        if (stTokenAmount < MIN_WITHDRAWAL || stTokenAmount > MAX_WITHDRAWAL) {
            revert AmountOutOfBounds(stTokenAmount);
        }

        uint256 shares = ST_TOKEN.getSharesByPooledEth(stTokenAmount);
        if (shares == 0) revert Errors.InvalidAmount();

        // Compute exact ETH value at current exchange rate before burning.
        // Stored so finalization doesn't require a separate rate parameter.
        uint256 ethValue = ST_TOKEN.getPooledEthByShares(shares);

        // Burn shares AND reduce totalPooledEther proportionally.
        // This keeps the exchange rate constant for remaining holders
        // (they don't receive a windfall from the withdrawal).
        uint256 currentPooled = ST_TOKEN.totalPooledEther();
        ST_TOKEN.burnShares(msg.sender, shares);
        if (currentPooled >= ethValue) {
            ST_TOKEN.setTotalPooledEther(currentPooled - ethValue);
        }

        requestId = nextRequestId++;
        requests[requestId] = WithdrawalRequest({
            owner: owner,
            stShares: shares,
            ethAmount: ethValue,  // locked at request-time exchange rate
            finalized: false,
            claimed: false
        });

        emit WithdrawalRequested(owner, requestId, shares, stTokenAmount);
    }

    // ── Finalize ──────────────────────────────────────────────────────────────

    /// @notice Finalize all pending requests up to and including `lastRequestId`.
    ///         Caller must send at least enough ETH to cover the sum of request ethAmounts.
    ///         ETH amounts were locked at request time; no share rate recalculation here.
    /// @param lastRequestId Last request ID to finalize (inclusive).
    function finalize(uint256 lastRequestId)
        external
        payable
        onlyRole(GUARDIAN)
        nonReentrant
    {
        uint256 fromId = lastFinalizedRequestId + 1;
        if (lastRequestId < fromId || lastRequestId >= nextRequestId) {
            revert InvalidRequestRange(fromId, lastRequestId);
        }

        uint256 totalEthRequired;
        for (uint256 id = fromId; id <= lastRequestId; ++id) {
            WithdrawalRequest storage req = requests[id];
            req.finalized = true;
            totalEthRequired += req.ethAmount; // ethAmount locked at request time
        }

        if (msg.value < totalEthRequired) {
            revert InsufficientFinalizeEth(totalEthRequired, msg.value);
        }

        lockedEther += totalEthRequired;
        lastFinalizedRequestId = lastRequestId;

        // Return any excess ETH to the caller.
        if (msg.value > totalEthRequired) {
            payable(msg.sender).sendValue(msg.value - totalEthRequired);
        }

        emit BatchFinalized(fromId, lastRequestId, totalEthRequired);
    }

    // ── Claim ─────────────────────────────────────────────────────────────────

    /// @notice Claim ETH for a finalized withdrawal request.
    /// @param requestId  The request to claim.
    /// @param recipient  Address to send ETH to.
    function claimWithdrawal(uint256 requestId, address payable recipient)
        external
        nonReentrant
    {
        WithdrawalRequest storage req = requests[requestId];

        if (!req.finalized) revert RequestNotFinalized(requestId);
        if (req.claimed) revert RequestAlreadyClaimed(requestId);
        if (req.owner != msg.sender) revert NotRequestOwner(requestId, msg.sender);
        if (recipient == address(0)) revert Errors.ZeroAddress();

        req.claimed = true;
        uint256 ethAmount = req.ethAmount;
        lockedEther -= ethAmount;

        recipient.sendValue(ethAmount);
        emit WithdrawalClaimed(msg.sender, recipient, requestId, ethAmount);
    }

    /// @notice Batch claim multiple finalized requests in one transaction.
    function claimWithdrawals(uint256[] calldata requestIds, address payable recipient)
        external
        nonReentrant
    {
        if (recipient == address(0)) revert Errors.ZeroAddress();
        uint256 totalEth;
        for (uint256 i; i < requestIds.length; ++i) {
            uint256 id = requestIds[i];
            WithdrawalRequest storage req = requests[id];

            if (!req.finalized) revert RequestNotFinalized(id);
            if (req.claimed) revert RequestAlreadyClaimed(id);
            if (req.owner != msg.sender) revert NotRequestOwner(id, msg.sender);

            req.claimed = true;
            totalEth += req.ethAmount;
            emit WithdrawalClaimed(msg.sender, recipient, id, req.ethAmount);
        }
        lockedEther -= totalEth;
        recipient.sendValue(totalEth);
    }

    // ── Views ─────────────────────────────────────────────────────────────────

    function getRequest(uint256 requestId) external view returns (WithdrawalRequest memory) {
        return requests[requestId];
    }

    function getRequestStatus(uint256 requestId)
        external
        view
        returns (bool finalized, bool claimed, uint256 ethAmount)
    {
        WithdrawalRequest storage req = requests[requestId];
        return (req.finalized, req.claimed, req.ethAmount);
    }

    /// @notice ETH available in this contract (total balance minus locked-for-claims).
    function availableEther() external view returns (uint256) {
        return address(this).balance - lockedEther;
    }

    /// @notice Accept plain ETH deposits (e.g., from StakingCore funding withdrawal queue).
    receive() external payable {}
}
