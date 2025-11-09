# WithdrawalQueue Contract Security Audit - Revised

## Executive Summary

After careful re-examination, this audit focuses on actual security vulnerabilities and logic errors, not design choices that are documented as intended behavior.

## Contract Overview

### Feature Set and Specification

**Purpose**: The `WithdrawalQueue` contract provides a redemption mechanism for liquid staking derivative tokens (WSGETH or VETH2) with:

- **Per-User Epoch Delay**: Each user must wait an epoch period before redeeming (not a global FIFO queue)
- **Two Modes**:
  - ERC4626 mode (virtualPrice = 0): Dynamic exchange rates via IERC4626
  - Fixed price mode (virtualPrice > 0): Fixed exchange rate
- **Operator Support**: ERC-7540 style operator permissions
- **Granular Pause**: Per-function pause mechanism

**Key Design Decisions (NOT BUGS)**:

1. **Per-User Queueing**: The FIFOQueue library comment says "cascading locks" - this is intentionally per-user, not global FIFO
2. **Epoch Reset**: Documented in contract comments (line 36): "If the user requests another redemption, before fulfillment, this resets the epoch length clock" - This is INTENTIONAL
3. **Assets vs Shares Tracking**: `redeemRequests` tracks assets (what needs to be paid out), while operations use shares (what tokens to burn) - this is correct design

**Core Functions**:

1. `requestRedeem(shares, requester, owner)`: Submit redemption request
2. `redeem(shares, receiver, requester)`: Fulfill redemption after epoch
3. `cancelRedeem(receiver, requester)`: Cancel request and get tokens back

---

## Security Findings

### 🔴 CRITICAL ISSUES

#### 1. **FIFO Queue Entry Mismatch: owner vs requester**

**Location**: `requestRedeem()` line 130 vs `redeem()` lines 162, 170

**Issue**: There's a mismatch between how FIFO queue entries are created and accessed:

- `requestRedeem`: Calls `_stakeForWithdrawal(owner, assets)` - creates FIFO entry for `owner`
- `redeem`: Calls `_checkWithdraw(requester, ...)` and `_withdraw(requester, assets)` - accesses FIFO entry for `requester`

**Impact**: HIGH - If `owner != requester`, the FIFO queue entry is created under `owner` but `redeem` tries to access `requester`'s entry, which doesn't exist. This would cause `_checkWithdraw` to fail because `userEntries[requester].amount` would be 0.

**Code Evidence**:

```solidity
// requestRedeem line 130
_stakeForWithdrawal(owner, assets);  // Creates entry for owner

// redeem line 162
_checkWithdraw(requester, totalBalance(), assets);  // Checks requester's entry

// redeem line 170
_withdraw(requester, assets);  // Updates requester's entry
```

**Analysis**: Looking at FIFOQueue.\_checkWithdraw():

```solidity
UserEntry memory ue = userEntries[sender];  // Gets requester's entry
if (!(amountToWithdraw <= balanceOfSelf && amountToWithdraw <= ue.amount)) {
    revert Errors.InvalidAmount();  // Will revert if ue.amount == 0
}
```

If `owner != requester`, `userEntries[requester]` will be empty (amount = 0), causing the check to fail with `InvalidAmount`.

**Test Evidence**: Test on line 253 shows `requestRedeem(parseEther("1"), alice.address, bob.address)` where `requester=alice` and `owner=bob` differ. However, this test only calls `requestRedeem`, not `redeem`. If `redeem` were called with `requester=alice`, it would fail because `userEntries[alice]` doesn't exist (entry was created for `bob`).

**Recommendation**: Change line 130 to use `requester` instead of `owner`:

```solidity
_stakeForWithdrawal(requester, assets);  // Use requester, not owner
```

**Reasoning**:

- `redeemRequests` already tracks by `requester` (line 132)
- `redeem()` accesses FIFO queue by `requester` (lines 162, 170)
- `claimableRedeemRequest()` checks by `requester` (line 278)
- FIFO queue should track by `requester` for consistency

**Note**: The `owner` parameter is still needed for `transferFrom(owner, ...)` to transfer tokens from the correct address, but FIFO queue tracking should use `requester`.

---

### 🟡 MEDIUM ISSUES

#### 2. **Missing Access Control Tests**

**Location**: Test files

**Issue**: No tests found for:

- `togglePause()` - should only be callable by GOV role
- `setEpochLength()` - should only be callable by GOV role
- Unauthorized users attempting admin functions

**Impact**: MEDIUM - Cannot verify access controls work correctly.

**Recommendation**: Add tests:

```typescript
it("should revert when non-GOV tries to togglePause", async () => {
  await expect(withdrawalQueue.connect(alice).togglePause(1)).to.be.reverted; // AccessControl error
});
```

#### 3. **Missing Granular Pause Tests**

**Location**: Test files

**Issue**: No tests found for granular pause functionality:

- Pausing `requestRedeem` (func 1) should not affect `redeem` (func 2)
- Pausing `redeem` (func 2) should not affect `cancelRedeem` (func 3)
- Each function should be independently pausable

**Impact**: MEDIUM - Cannot verify granular pause works as intended.

**Recommendation**: Add comprehensive pause tests.

#### 4. **Potential Accounting Issue in `cancelRedeem()` When Exchange Rate Changes**

**Location**: `cancelRedeem()` lines 224-240

**Issue**: When canceling, the function:

1. Gets `assets = pendingRedeemRequest(requester)` (original assets tracked)
2. Converts to shares using CURRENT exchange rate: `shares = _convertAssetsToShares(assets)`
3. If shares > contractShares, recalculates `assets` based on available shares
4. Deducts the RECALCULATED `assets` from `redeemRequests[requester]`

**Impact**: MEDIUM - If exchange rate changes unfavorably and contract doesn't have enough shares, the `assets` variable is recalculated to a smaller value, but this smaller value is deducted from `redeemRequests`. This could leave some assets "stuck" in `redeemRequests` if the recalculation results in fewer assets than originally tracked.

**Example Scenario**:

- User requests 10 shares when 1 share = 1.1 ETH → `redeemRequests` = 11 ETH
- Exchange rate changes to 1 share = 1.0 ETH
- Cancel converts 11 ETH → 11 shares, but contract only has 10 shares
- Recalculates: 10 shares → 10 ETH
- Deducts 10 ETH from `redeemRequests[requester]`
- But `redeemRequests` was tracking 11 ETH, so 1 ETH remains tracked but unclaimable

**Code Evidence**:

```solidity
assets = pendingRedeemRequest(requester);  // Original: 11 ETH
shares = _convertAssetsToShares(assets);   // Converts to 11 shares
if (shares > contractShares) {              // Only 10 shares available
    shares = contractShares;               // Use 10 shares
    assets = ...;                          // Recalculate: 10 ETH
}
redeemRequests[requester] -= assets;       // Deducts 10 ETH, but tracked 11 ETH
```

**Recommendation**: Track original shares in `requests` mapping and return exact shares on cancel, or ensure `redeemRequests` is decremented by the original amount, not recalculated amount.

#### 5. **State Updates Before External Calls in `redeem()`**

**Location**: `redeem()` lines 170-189

**Issue**: State is updated (lines 170-176) before external calls to minter contract (lines 178-189). If minter call fails, state is already updated but funds weren't transferred.

**Impact**: MEDIUM - However, with `nonReentrant` guard, this is safer. The main risk is if minter contract has issues, accounting could be inconsistent.

**Code Evidence**:

```solidity
// Lines 170-176: State updated
_withdraw(requester, assets);
redeemRequests[requester] -= assets;
totalPendingRequest -= assets;
totalAssetsOut += assets;
requestsFulfilled++;

// Lines 178-189: External call AFTER state update
if (assets > minterBalance) {
    payable(MINTER).transfer(diff);
}
SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
```

**Analysis**: With `nonReentrant` guard, reentrancy is prevented. However, if minter reverts, the entire transaction reverts (including state changes), so this is actually safe. The state updates happen atomically with the external call.

**Recommendation**: This is actually safe due to atomic transactions, but could be clearer. Consider adding comments or restructuring for clarity.

---

### 🟢 LOW ISSUES / SUGGESTIONS

#### 6. **Math Precision in Fixed Price Mode**

**Location**: `_convertSharesToAssets()` line 306, `_convertAssetsToShares()` line 320

**Issue**: Division operations could lose precision for very small amounts.

**Impact**: LOW - Standard Solidity precision loss, acceptable for most use cases.

**Recommendation**: Document precision limits.

#### 7. **Unused `requests` Mapping**

**Location**: Line 62

**Issue**: `mapping(uint256 => Request) internal requests;` is populated (line 126) but never read internally. However, it's likely used for off-chain indexing via events.

**Impact**: LOW - Gas cost, but may be intentional for event indexing.

**Recommendation**: Document that this is for off-chain indexing if that's the intent.

#### 8. **Inconsistent Parameter Usage**

**Location**: `requestRedeem()` line 130

**Issue**: Function takes both `requester` and `owner` parameters, but FIFO queue uses `owner` while `redeemRequests` uses `requester`. This could be confusing.

**Impact**: LOW - Works correctly if `owner == requester`, but could be clearer.

**Recommendation**: Consider using `requester` consistently for FIFO queue operations, or document the relationship between owner and requester.

---

## Test Coverage Analysis

### ✅ Well Tested

- Basic request/redeem flows
- Operator functionality
- Edge cases (zero addresses, zero amounts)
- Fixed price mode
- Partial redemptions
- Multiple users
- Epoch timing

### ❌ Missing Tests

1. **Granular Pause Tests**: No tests for pausing individual functions
2. **Admin Access Control Tests**: No tests for GOV role restrictions
3. **Owner != Requester Scenarios**: No tests verifying behavior when owner differs from requester
4. **Exchange Rate Change Tests**: No tests for rate changes between request and redeem/cancel
5. **Minter Failure Tests**: No tests for minter contract failures
6. **Cancel with Insufficient Shares**: Limited testing of cancel edge cases

---

## Architecture Review

### FIFO Queue Design

**Current Design**: Per-user epoch-based delay system

- Each user has their own `UserEntry` with `amount` and `blocknum`
- Users must wait `epochLength` blocks after their last request before redeeming
- This is NOT a global FIFO queue - users can redeem independently once their epoch elapses

**This is INTENTIONAL** based on FIFOQueue library comments: "cascading locks based on block number" and "Users past the epoch boundary can claim, allowing some time for earlier users to claim first"

**Not a Bug**: The per-user design is intentional, not a bug.

### Accounting Design

**Assets vs Shares**:

- `redeemRequests[requester]` tracks assets (what needs to be paid out)
- Operations use shares (what tokens to burn/transfer)
- Conversion happens at request time and redeem time
- This is correct design - assets represent the value owed, shares represent the tokens held

**Not a Bug**: The dual tracking system is intentional and correct.

---

## Recommendations Summary

### Critical Fixes Required

1. **Fix FIFO Queue Entry Mismatch**: Use `requester` consistently for FIFO queue operations, or document that `owner` must equal `requester`

### High Priority

2. **Add Access Control Tests**: Test GOV role restrictions
3. **Add Granular Pause Tests**: Test independent function pausing
4. **Fix Cancel Accounting**: Ensure `redeemRequests` is decremented correctly when shares are insufficient

### Medium Priority

5. **Add Owner != Requester Tests**: Verify behavior when parameters differ
6. **Add Exchange Rate Change Tests**: Test behavior when rates change
7. **Document Design Decisions**: Clarify per-user vs global FIFO, assets vs shares tracking

---

## Conclusion

After careful re-examination, the main issue is the potential mismatch between `owner` and `requester` in FIFO queue operations. Most other "issues" identified initially were actually documented design choices:

- Per-user queueing (not global FIFO) - INTENTIONAL
- Epoch reset on new requests - DOCUMENTED and INTENTIONAL
- Assets vs shares tracking - CORRECT DESIGN

**Overall Assessment**:

- **Security**: ⚠️ MEDIUM RISK - One potential bug with owner/requester mismatch
- **Correctness**: ✅ MOSTLY CORRECT - One potential issue to verify
- **Test Coverage**: ⚠️ INCOMPLETE - Missing pause and access control tests

**Recommendation**: Fix the owner/requester mismatch issue and add missing tests. The contract design is sound overall.
