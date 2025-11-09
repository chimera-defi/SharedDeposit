# Multipass Security Review - Critical Vulnerabilities Found and Fixed

## Date: Current Review Session

## Critical Vulnerabilities Identified and Fixed

### 1. ✅ FIXED: Accounting Bug in `cancelRedeem` and `cancelRedeemFor`

**Issue**: When `shares > contractShares`, the code was adjusting `assets` down but only subtracting the adjusted amount from `redeemRequests[requester]` and `totalPendingRequest`, leaving stuck funds that could never be cleared.

**Impact**: 
- Accounting leak: `redeemRequests[requester]` and `totalPendingRequest` would have remainders
- FIFO queue inconsistency: `userEntries[requester].amount` would have remainders
- Funds stuck in contract forever

**Fix**: Changed to revert with `Errors.InsufficientBalance()` if `shares > contractShares` instead of partial cancellation. This ensures full cancellation or revert, preventing accounting inconsistencies.

**Location**: Lines 322-326 and 367-371

### 2. ✅ FIXED: Potential Underflow in `redeem` and `redeemFor`

**Issue**: If exchange rate changed such that `assets` (calculated from current rate) > `redeemRequests[requester]` (stored from original request), subtracting `assets` from `redeemRequests[requester]` would underflow.

**Impact**: 
- Underflow would revert (Solidity 0.8+), but this is a logic error that should be caught earlier
- Inconsistent accounting between `redeemRequests[requester]` and `userEntries[requester].amount`

**Fix**: Added explicit check `if (assets > redeemRequests[requester]) { revert Errors.InvalidAmount(); }` before subtraction. This provides clear error message and prevents underflow.

**Note**: `_checkWithdraw` already checks `ue.amount >= assets`, but adding explicit check for `redeemRequests` provides defense-in-depth.

**Location**: Lines 201-205 and 273-277

## Review of `onlyOwnerOrOperator(msg.sender)` Usage

### Analysis

The user raised concern about `onlyOwnerOrOperator(msg.sender)` checks using `msg.sender` instead of passed-in addresses.

**Functions Using `onlyOwnerOrOperator(msg.sender)`**:
1. `requestRedeem(uint256 shares)` - Line 114
2. `redeem(uint256 shares, address receiver)` - Line 178  
3. `cancelRedeem(address receiver)` - Line 303

**Assessment**: ✅ **CORRECT USAGE**

These are **self-service functions** where:
- `msg.sender` is used as both `requester` and `owner` (or just `requester`)
- The modifier checks that `msg.sender` is authorized to act on their own behalf
- The modifier will always pass (since `msg.sender == msg.sender`), which is correct - anyone can act on their own behalf
- This is intentional design: these are simplified functions for users to call directly

**Functions Using `onlyOwnerOrOperator(address)` with passed-in address**:
1. `requestRedeemFor(uint256 shares, address requester, address owner)` - Line 144: checks `owner`
2. `redeemFor(uint256 shares, address receiver, address requester)` - Line 241: checks `requester`
3. `cancelRedeemFor(address receiver, address requester)` - Line 351: checks `requester`

**Assessment**: ✅ **CORRECT USAGE**

These are **operator functions** where:
- The modifier checks authorization for the passed-in address (owner or requester)
- This allows operators to act on behalf of users
- Authorization is correctly validated before operations

## Other Security Checks Performed

### ✅ Access Control
- All external functions have appropriate access control:
  - Simple functions: `onlyOwnerOrOperator(msg.sender)` - self-service
  - Operator functions: `onlyOwnerOrOperator(address)` - operator-controlled
  - Admin functions: `onlyRole(GOV)` - governance-controlled
- No unprotected state-changing functions found

### ✅ Reentrancy Protection
- All external functions use `nonReentrant` modifier
- Checks-effects-interactions pattern followed

### ✅ Input Validation
- Zero address checks for all address parameters
- Zero amount checks for all amount parameters
- Array bounds checking where applicable

### ✅ Granular Pause
- All 7 external functions have unique pause IDs (1-7)
- Pause checks applied to all state-changing functions

### ✅ Math Safety
- Solidity 0.8+ provides automatic overflow/underflow protection
- Explicit checks added for edge cases (exchange rate changes)
- All subtractions validated before execution

### ✅ FIFO Queue Consistency
- `_stakeForWithdrawal` uses `requester` address consistently
- `_withdraw` uses `requester` address consistently
- `_checkWithdraw` validates against correct user entry

### ✅ Accounting Consistency
- `redeemRequests[requester]` and `totalPendingRequest` updated together
- `userEntries[requester].amount` matches `redeemRequests[requester]` initially
- Explicit checks prevent divergence due to exchange rate changes

## Remaining Considerations

### 1. Exchange Rate Changes
The contract handles exchange rate changes by:
- Using current rate for conversions (`_convertSharesToAssets`, `_convertAssetsToShares`)
- Validating that redemption amounts don't exceed recorded requests
- Reverting if inconsistencies detected

**Status**: ✅ Handled correctly with explicit checks

### 2. Partial Redemptions
The contract allows partial redemptions (user can redeem less than their full request), but:
- Full cancellation requires sufficient shares (reverts if not)
- Redemption validates against recorded amounts

**Status**: ✅ Handled correctly

### 3. Operator Permissions
Operators can act on behalf of users only if:
- User has set them as operator via `setOperator(operator, true)`
- Or operator is the user themselves

**Status**: ✅ Correctly enforced via `onlyOwnerOrOperator` modifier

## Conclusion

**Critical Vulnerabilities**: 2 found and fixed
1. Accounting bug in cancel functions (partial cancellation)
2. Potential underflow in redeem functions (exchange rate changes)

**Access Control**: ✅ All functions properly protected
**Reentrancy**: ✅ All functions protected
**Math Safety**: ✅ Protected (Solidity 0.8+ + explicit checks)
**Accounting**: ✅ Consistent with fixes applied

The `onlyOwnerOrOperator(msg.sender)` usage is **correct** for self-service functions. The modifier ensures users can only act on their own behalf, which is the intended behavior.

## Recommendations

1. ✅ **COMPLETED**: Fixed accounting bug in cancel functions
2. ✅ **COMPLETED**: Added underflow protection in redeem functions
3. Consider adding comprehensive tests for exchange rate change scenarios
4. Consider adding tests for partial redemptions with exchange rate changes
5. Consider documenting the exchange rate change handling behavior more explicitly
