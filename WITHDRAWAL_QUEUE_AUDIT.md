# WithdrawalQueue Contract Security Audit

## Executive Summary

This audit reviews the `WithdrawalQueue` contract for security vulnerabilities, correctness, and test coverage. The contract implements an ERC-7540 inspired withdrawal queue system with FIFO ordering and epoch delays.

## Contract Overview

### Feature Set and Specification

**Purpose**: The `WithdrawalQueue` contract provides a redemption mechanism for liquid staking derivative tokens (WSGETH or VETH2) with:
- **FIFO Queue**: Users must wait an epoch period before redeeming
- **Two Modes**: 
  - ERC4626 mode (virtualPrice = 0): Dynamic exchange rates via IERC4626
  - Fixed price mode (virtualPrice > 0): Fixed exchange rate
- **Operator Support**: ERC-7540 style operator permissions
- **Granular Pause**: Per-function pause mechanism

**Core Functions**:
1. `requestRedeem`: Submit a redemption request (transfers tokens, tracks assets)
2. `redeem`: Fulfill redemption after epoch delay
3. `cancelRedeem`: Cancel request and get tokens back (after epoch)

**Key State Variables**:
- `redeemRequests[address]`: Tracks pending assets per requester
- `totalPendingRequest`: Total assets pending redemption
- `requestsCreated/Fulfilled`: Request counters
- `userEntries`: FIFO queue entries (from FIFOQueue library)

---

## Security Findings

### 🔴 CRITICAL ISSUES

#### 1. **Not a True FIFO Queue - Per-User Queueing Only**

**Location**: `FIFOQueue.sol` + `WithdrawalQueue.sol`

**Issue**: The contract does NOT enforce global FIFO ordering across all users. Each user has their own queue entry (`userEntries[address]`), meaning:
- User A requests 100 ETH at block 100
- User B requests 50 ETH at block 101
- User A can redeem ALL 100 ETH before User B redeems ANY, even though User B requested later

**Impact**: HIGH - This defeats the purpose of a FIFO queue. Early users can front-run later users by making large requests, then redeeming everything before later users get their turn.

**Code Evidence**:
```solidity
// FIFOQueue.sol:63-68
function _stakeForWithdrawal(address sender, uint256 amount) internal {
    UserEntry memory ue = userEntries[sender];  // Per-user mapping
    ue.amount = ue.amount + amount;
    ue.blocknum = block.number;
    userEntries[sender] = ue;
}
```

**Recommendation**: Implement a global queue with request IDs that must be processed in order. Track `requestsCreated` and `requestsFulfilled` to enforce ordering.

#### 2. **Epoch Reset Vulnerability**

**Location**: `requestRedeem()` line 130

**Issue**: When a user makes a new redemption request, `_stakeForWithdrawal()` resets their `blocknum` to `block.number`, effectively resetting their epoch timer.

**Impact**: MEDIUM-HIGH - Users can game the system by:
1. Requesting redemption at block 100
2. Waiting until block 199 (1 block before epoch completes)
3. Making another small request, resetting epoch to block 199
4. This delays their redemption but allows them to "refresh" their position

**Code Evidence**:
```solidity
// FIFOQueue.sol:63-68
function _stakeForWithdrawal(address sender, uint256 amount) internal {
    UserEntry memory ue = userEntries[sender];
    ue.amount = ue.amount + amount;
    ue.blocknum = block.number;  // ⚠️ Always resets to current block
    userEntries[sender] = ue;
}
```

**Recommendation**: Only update `blocknum` if it's the first request OR if the new request's blocknum would be later than existing. Or track per-request epochs instead of per-user.

#### 3. **Incorrect Accounting in `redeem()` - Shares vs Assets Mismatch**

**Location**: `redeem()` lines 156-198

**Issue**: The function accepts `shares` as input, converts to `assets`, but then:
- Deducts `assets` from `redeemRequests[requester]` (line 172)
- But burns/transfers `shares` amount (line 189/195)
- The `redeemRequests` tracks assets, but actual token operations use shares

**Impact**: MEDIUM - If exchange rate changes between request and redeem:
- User requests 10 shares when 1 share = 1.1 ETH → `redeemRequests` = 11 ETH
- Exchange rate changes to 1 share = 1.2 ETH
- User redeems 10 shares → deducts 12 ETH from `redeemRequests`, but only burns 10 shares
- Accounting mismatch: `redeemRequests` tracks assets, but operations use shares

**Code Evidence**:
```solidity
// Line 156: Convert shares to assets
assets = _convertSharesToAssets(shares);

// Line 172: Deduct assets from tracking
redeemRequests[requester] -= assets;

// Line 189: But burn/transfer shares
SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
```

**Recommendation**: Track shares in `redeemRequests` instead of assets, OR ensure all operations consistently use the same unit (assets).

#### 4. **Potential Underflow in `cancelRedeem()` When Exchange Rate Changes**

**Location**: `cancelRedeem()` lines 224-237

**Issue**: When canceling, the function converts assets back to shares using CURRENT exchange rate. If the rate changed unfavorably:
- User requested 10 shares → 11 ETH assets (rate was 1.1)
- Rate changes to 1.0 (shares devalued)
- Cancel converts 11 ETH → 11 shares
- But contract only holds 10 shares
- Code handles this (lines 229-237), but adjusts `assets` AFTER already calculating shares

**Impact**: MEDIUM - Edge case where user gets fewer shares back than they deposited if exchange rate devalues. Additionally, the `assets` variable is recalculated, which means `redeemRequests[requester]` is decremented by a DIFFERENT amount than what was originally tracked, causing accounting inconsistency.

**Code Evidence**:
```solidity
// Line 224: Convert using CURRENT rate (may differ from request time)
uint256 shares = _convertAssetsToShares(assets);

// Line 229-237: Adjust if shares > contractShares
if (shares > contractShares) {
    shares = contractShares;
    // Recalculate assets based on available shares
    assets = ...;  // ⚠️ Assets changed!
}

// Line 240: Deduct RECALCULATED assets, not original
redeemRequests[requester] -= assets;
```

**Recommendation**: Track original shares deposited in `requests` mapping, return those exact shares on cancel. Don't recalculate assets.

---

### 🟡 MEDIUM ISSUES

#### 5. **Missing Access Control Tests**

**Location**: Test files

**Issue**: No tests found for:
- `togglePause()` - should only be callable by GOV role
- `setEpochLength()` - should only be callable by GOV role
- Unauthorized users attempting admin functions

**Impact**: MEDIUM - Cannot verify access controls work correctly.

**Recommendation**: Add tests:
```typescript
it("should revert when non-GOV tries to togglePause", async () => {
  await expect(
    withdrawalQueue.connect(alice).togglePause(1)
  ).to.be.revertedWith("AccessControl");
});
```

#### 6. **Missing Granular Pause Tests**

**Location**: Test files

**Issue**: No tests found for granular pause functionality:
- Pausing `requestRedeem` (func 1) should not affect `redeem` (func 2)
- Pausing `redeem` (func 2) should not affect `cancelRedeem` (func 3)
- Each function should be independently pausable

**Impact**: MEDIUM - Cannot verify granular pause works as intended.

**Recommendation**: Add comprehensive pause tests:
```typescript
it("should pause requestRedeem independently", async () => {
  await withdrawalQueue.connect(multiSig).togglePause(1);
  await expect(
    withdrawalQueue.connect(alice).requestRedeem(...)
  ).to.be.revertedWithCustomError(withdrawalQueue, "IsPaused");
  
  // But redeem should still work
  await withdrawalQueue.connect(alice).redeem(...); // Should succeed
});
```

#### 7. **Reentrancy Guard Coverage**

**Location**: All external functions

**Status**: ✅ GOOD - All state-changing external functions have `nonReentrant` modifier:
- `requestRedeem()` - line 119
- `redeem()` - line 148  
- `cancelRedeem()` - line 210

**Note**: External calls happen AFTER state updates (checks-effects-interactions pattern), which is correct.

#### 8. **Potential DoS via `totalBalance()` in ERC4626 Mode**

**Location**: `totalBalance()` line 288-294

**Issue**: In ERC4626 mode, `totalBalance()` reads `MINTER.balance`. If minter contract is paused or has issues, this could cause `claimableRedeemRequest()` to fail.

**Impact**: LOW-MEDIUM - View function failure could break frontends, but doesn't affect core functionality.

**Recommendation**: Add try-catch or handle minter balance read failures gracefully.

#### 9. **Unsafe External Call in `redeem()` ERC4626 Mode**

**Location**: `redeem()` lines 178-189

**Issue**: The contract transfers ETH to MINTER if balance is insufficient (line 185), then calls `unstakeAndWithdraw()`. If minter reverts or behaves unexpectedly, the entire redeem fails. Additionally, state has already been updated (lines 170-176) before the external call, which violates checks-effects-interactions pattern.

**Impact**: MEDIUM-HIGH - State updates happen before external call, meaning if minter fails, accounting is already updated but funds weren't transferred. This could lead to accounting inconsistencies.

**Code Evidence**:
```solidity
// Lines 170-176: State updated BEFORE external call
_withdraw(requester, assets);
redeemRequests[requester] -= assets;
totalPendingRequest -= assets;
totalAssetsOut += assets;
requestsFulfilled++;

// Lines 178-189: External call AFTER state update
if (assets > minterBalance) {
    payable(MINTER).transfer(diff);  // ⚠️ Could fail
}
SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);  // ⚠️ Could fail
```

**Recommendation**: Move external calls before state updates, or use a two-phase commit pattern. Alternatively, ensure minter is trusted and cannot fail.

---

### 🟢 LOW ISSUES / SUGGESTIONS

#### 10. **Math Precision in Fixed Price Mode**

**Location**: `_convertSharesToAssets()` line 306, `_convertAssetsToShares()` line 320

**Issue**: Division by `1e18` could lose precision for very small amounts. Additionally, `_convertAssetsToShares()` divides `assets * 1e18` by `VIRTUAL_PRICE`, which could cause precision loss if `VIRTUAL_PRICE` is not a multiple of precision factors.

**Impact**: LOW - Standard Solidity precision loss, acceptable for most use cases. However, precision loss could accumulate over many operations.

**Recommendation**: Document precision limits. Consider using higher precision (e.g., 1e27) for internal calculations if needed.

#### 14. **Inconsistent Parameter Naming**

**Location**: `requestRedeem()` line 118

**Issue**: Function takes `owner` parameter but uses it as `sender` in `_stakeForWithdrawal(owner, assets)`. The FIFO queue tracks by `owner` address, but the requester might be different.

**Impact**: LOW - Confusing but works correctly. The `owner` is the token owner, `requester` is who initiated the request.

**Recommendation**: Clarify documentation or rename for clarity.

#### 15. **Missing Validation in `redeem()` for Shares Consistency**

**Location**: `redeem()` lines 144-198

**Issue**: Function accepts `shares` parameter but doesn't validate that the requester actually has a request for those shares. It only checks `claimableRedeemRequest(requester) >= assets`, but doesn't verify the shares match any specific request.

**Impact**: LOW - User can redeem any amount up to their total pending, which is correct behavior. But there's no way to verify which specific request is being fulfilled.

**Recommendation**: Consider tracking per-request fulfillment if needed, or document that partial redemptions are allowed.

#### 12. **Missing Zero Address Check for MINTER in Constructor**

**Location**: Constructor lines 88-91

**Status**: ✅ GOOD - Checks `_minter == address(0)` for ERC4626 mode.

#### 13. **Inconsistent Error Handling**

**Location**: Various

**Issue**: Some functions use custom errors, some might use require strings (though all appear to use custom errors).

**Status**: ✅ GOOD - All errors use custom errors from `Errors.sol`.

---

## Test Coverage Analysis

### ✅ Well Tested
- Basic request/redeem flows
- Operator functionality
- Edge cases (zero addresses, zero amounts)
- Fixed price mode
- Partial redemptions
- Multiple users

### ❌ Missing Tests
1. **Granular Pause Tests**: No tests for pausing individual functions
2. **Admin Access Control Tests**: No tests for GOV role restrictions
3. **Epoch Reset Tests**: No tests verifying epoch reset behavior
4. **FIFO Ordering Tests**: No tests verifying global FIFO ordering (because it doesn't exist)
5. **Exchange Rate Change Tests**: No tests for rate changes between request and redeem
6. **Minter Failure Tests**: No tests for minter contract failures
7. **Concurrent Request Tests**: Limited tests for multiple users requesting simultaneously

---

## Architecture Issues

### FIFO Queue Implementation

**Current Design**: Per-user queue entries
- Each user tracks their own `amount` and `blocknum`
- No global ordering enforced
- Users can redeem out of order relative to other users

**Expected Design**: Global FIFO queue
- Requests processed in order of `requestId`
- Earlier requests must be fulfilled before later ones
- Enforces true first-in-first-out behavior

**Recommendation**: Redesign to use `requestsCreated` and `requestsFulfilled` to enforce global ordering:
```solidity
function redeem(...) {
    // Must process requests in order
    require(requestsFulfilled == nextRequestIdToProcess, "Must process in order");
    // Process request
    requestsFulfilled++;
}
```

---

## Recommendations Summary

### Critical Fixes Required

1. **Implement True FIFO Queue**: Use global request ordering instead of per-user queues
2. **Fix Epoch Reset**: Don't reset epoch timer on new requests from same user
3. **Fix Accounting Mismatch**: Use consistent units (shares or assets) throughout
4. **Track Original Shares**: Store original shares on request, return exact shares on cancel

### High Priority

5. **Add Access Control Tests**: Test GOV role restrictions
6. **Add Granular Pause Tests**: Test independent function pausing
7. **Add Exchange Rate Change Tests**: Test behavior when rates change

### Medium Priority

8. **Handle Minter Failures**: Add error handling for minter contract issues
9. **Document Precision Limits**: Document math precision constraints
10. **Remove Unused Code**: Clean up unused `requests` mapping or document its purpose

---

## Conclusion

The `WithdrawalQueue` contract has several critical architectural issues that prevent it from functioning as a true FIFO queue. The per-user queueing system allows users to redeem out of order, defeating the purpose of queue-based withdrawals. Additionally, accounting inconsistencies between shares and assets could lead to incorrect tracking.

**Overall Assessment**: 
- **Security**: ⚠️ MEDIUM RISK - Critical issues present but not immediately exploitable
- **Correctness**: ⚠️ NEEDS FIXES - FIFO ordering not enforced, accounting inconsistencies
- **Test Coverage**: ⚠️ INCOMPLETE - Missing critical tests for pause and access control

**Recommendation**: Address critical issues before mainnet deployment, especially the FIFO queue implementation and accounting consistency.
