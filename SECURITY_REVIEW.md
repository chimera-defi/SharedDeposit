# SharedStake Modular-Staking Security Review

**Date:** 2026-05-06
**Scope:** `contracts/v2/modular-staking/` (StakingCore, StakingRouter, ValidatorModule, DVTModule, LSTWrapModule, StToken, WstToken, WithdrawalQueueV2, FeeController, OracleAdapter, QuorumOracleAdapter, InstitutionalPolicyRegistry, LidoPriceOracle, ShareMath)
**Tool:** Slither v0.11.x + manual review
**Result:** No critical or high severity issues. All reentrancy warnings are false positives due to trusted internal contracts or existing `nonReentrant` guards.

---

## Executive Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0 | ✅ |
| High | 0 | ✅ |
| Medium | 0 | ✅ |
| Low / Info | 8 | Reviewed, all acceptable or false positives |

---

## Findings

### 1. Reentrancy in `StakingRouter.reportModuleBeaconBalance` — FALSE POSITIVE
**Severity:** Low (Slither classification: High)
**Location:** `StakingRouter.sol:280-292`
**Details:** Slither flags `_applyBeaconDelta` which calls `ST_TOKEN.setTotalPooledEther` and `ST_TOKEN.mintShares` before updating `moduleBeaconBalance[moduleId]`.
**Assessment:** `ST_TOKEN` is the protocol's own rebasing token (trusted, no reentrancy hooks). The function is protected by `nonReentrant`. The external call is to an immutable internal contract.
**Recommendation:** No change required. The ordering is intentional (apply delta first, then update baseline).

### 2. Reentrancy in `WithdrawalQueueV2._enqueueRequest` — FALSE POSITIVE
**Severity:** Low (Slither classification: High)
**Location:** `WithdrawalQueueV2.sol:121-153`
**Details:** Slither flags `ST_TOKEN.burnShares` and `ST_TOKEN.setTotalPooledEther` as external calls before state updates.
**Assessment:** `ST_TOKEN` is trusted internal contract. Function is protected by `nonReentrant`. `burnShares` does not call back into WithdrawalQueueV2.
**Recommendation:** No change required.

### 3. Reentrancy in `LSTWrapModule.wrapLST` / `unwrapLST` — ACCEPTABLE RISK
**Severity:** Low (Slither classification: Medium)
**Location:** `LSTWrapModule.sol:80-131`
**Details:** External calls to arbitrary `LST_TOKEN` before state updates.
**Assessment:** The LST token address is set by GOV during module registration. `SafeERC20` is used for transfers. Both functions have `nonReentrant`. A malicious LST token could attempt reentrancy but would be blocked by `nonReentrant` on the module and the router.
**Recommendation:** No change required. The risk is bounded by GOV-controlled token whitelist.

### 4. Reentrancy in `StakingCore._distributeFees` — FALSE POSITIVE
**Severity:** Low (Slither classification: Medium)
**Location:** `StakingCore.sol:193-224`
**Details:** External calls to `ST_TOKEN.mintShares` before event emission.
**Assessment:** `ST_TOKEN` is trusted internal contract. No callbacks possible.
**Recommendation:** No change required.

### 5. `WstToken.wrap/unwrap` ignores transfer return value — LOW
**Severity:** Low
**Location:** `WstToken.sol:45,63`
**Details:** `transferFrom` and `transfer` return values are not checked.
**Assessment:** `ST_TOKEN` is the protocol's own token which always returns `true`. This is not an external token.
**Recommendation:** No change required. Could add `require(success)` for completeness but adds no real safety.

### 6. `FeeController.computeFees` multiplication-after-division — INFO
**Severity:** Info
**Location:** `FeeController.sol:71-72`
**Details:** `totalFee = (rewards * feeBps) / 10000` followed by `treasuryAmount = (totalFee * treasurySplitBps) / 10000`.
**Assessment:** Standard fee math. Precision loss is at most 1 wei per division, acceptable for financial calculations at ETH scale.
**Recommendation:** No change required. If exact precision is needed, use `mulDiv` from solmate or OZ, but the current math is identical to Lido's implementation.

### 7. Local variables "never initialized" — FALSE POSITIVE
**Severity:** Info
**Location:** `WithdrawalQueueV2.sol:177,265`, `StakingRouter.sol:384`
**Details:** Slither reports `totalEthRequired`, `totalEth`, `routing` as uninitialized.
**Assessment:** In Solidity, local variables of value type are zero-initialized by default. These are correctly used as accumulators.
**Recommendation:** No change required.

### 8. `StakingRouter.modules` return parameter shadows struct field — INFO
**Severity:** Info
**Location:** `StakingRouter.sol:613`
**Details:** Return parameter name `paused` shadows `ModuleInfo.paused`.
**Assessment:** Naming style issue, not a security vulnerability. Does not affect execution.
**Recommendation:** Optional rename to `isPaused` for clarity.

---

## Manual Review Checklist

| Check | Result | Notes |
|-------|--------|-------|
| All external functions access-controlled or guarded | ✅ | Every privileged function has `onlyRole` or `whenNotPaused` |
| Input validation (zero address, zero amount, bounds) | ✅ | All entrypoints validate inputs |
| Centralization risk documented | ✅ | GOV = timelock/multisig, GUARDIAN = fast-response key |
| Economic attack vectors | ✅ | First deposit bootstrap protected, no donation attack surface |
| Events for all state changes | ✅ | Comprehensive event coverage |
| No upgrade risks | ✅ | Contracts are NOT upgradeable (no proxy pattern) |
| Reentrancy protection | ✅ | `nonReentrant` on all sensitive entrypoints |
| Oracle sanity checks | ✅ | `maxDeltaBps`, `maxSlashBps`, staleness guards |
| Withdrawal queue bunker mode | ✅ | Oracle-controlled distress mode with batch limits |

---

## Remediation Plan

**No code changes required.** All findings are either false positives (trusted internal calls, existing `nonReentrant`) or informational (naming, precision loss at sub-wei level).

**Optional polish (non-security):**
1. Rename `StakingRouter.modules` return parameter from `paused` to `isPaused`
2. Add explicit `require(success)` on WstToken transfers (cosmetic)

**Operational recommendations:**
1. Use `QuorumOracleAdapter` (not single-submitter `OracleAdapter`) for mainnet
2. Set conservative initial caps: `mintCapEth = 320 ETH`, `maxDeltaBps = 500`
3. Monitor `WithdrawalQueueV2` bunker mode transitions closely post-launch
