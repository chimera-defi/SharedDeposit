# Remaining Tasks and Test Coverage Gaps

## Date: Current Review Session

## ✅ Completed Tasks

1. ✅ Fixed accounting bug in `cancelRedeem` and `cancelRedeemFor` (partial cancellation)
2. ✅ Fixed potential underflow in `redeem` and `redeemFor` (exchange rate changes)
3. ✅ Refactored functions to use `msg.sender` for simple cases
4. ✅ Added operator "For" variants (`requestRedeemFor`, `redeemFor`, `cancelRedeemFor`)
5. ✅ Added `requestRedeemForUser` GOV function
6. ✅ Updated all existing tests to match new function signatures
7. ✅ Fixed FIFO queue consistency (uses `requester` consistently)
8. ✅ Added unique granular pause IDs (1-7) to all functions
9. ✅ Added access control checks (`onlyOwnerOrOperator`) to all functions

---

## 🔴 Critical Missing Tests

### 1. Granular Pause Tests

**Status**: ❌ **NO TESTS FOUND**

**What to Test**:

- Each function can be paused independently (IDs 1-7)
- Paused functions revert with appropriate error
- Unpaused functions work normally
- Only GOV role can toggle pause
- Non-GOV role cannot toggle pause
- Multiple functions can be paused simultaneously
- Pausing one function doesn't affect others

**Test Cases Needed**:

```typescript
describe("Granular Pause", () => {
  it("should pause requestRedeem (ID 1) independently");
  it("should pause requestRedeemFor (ID 2) independently");
  it("should pause redeem (ID 3) independently");
  it("should pause redeemFor (ID 4) independently");
  it("should pause cancelRedeem (ID 5) independently");
  it("should pause cancelRedeemFor (ID 6) independently");
  it("should pause requestRedeemForUser (ID 7) independently");
  it("should revert when non-GOV tries to toggle pause");
  it("should allow multiple functions to be paused simultaneously");
  it("should unpause functions independently");
});
```

### 2. `requestRedeemForUser` (GOV Function) Tests

**Status**: ❌ **NO TESTS FOUND**

**What to Test**:

- Only GOV role can call `requestRedeemForUser`
- Non-GOV role cannot call it
- Function works correctly when called by GOV
- Proper event emission
- Accounting updates correctly
- FIFO queue entry created for requester
- Zero address validation for requester and owner
- Zero shares validation

**Test Cases Needed**:

```typescript
describe("requestRedeemForUser (GOV)", () => {
  it("should allow GOV role to request redemption for any user");
  it("should revert when non-GOV tries to call");
  it("should revert with zero requester address");
  it("should revert with zero owner address");
  it("should revert with zero shares");
  it("should emit RedeemRequest event with correct parameters");
  it("should update redeemRequests mapping correctly");
  it("should update totalPendingRequest correctly");
  it("should create FIFO queue entry for requester");
  it("should transfer tokens from owner to contract");
});
```

### 3. Exchange Rate Change Tests

**Status**: ⚠️ **PARTIALLY TESTED** (fixed price mode has some tests, but not comprehensive)

**What to Test**:

- When exchange rate increases: `assets` (current) > `redeemRequests[requester]` (original)
  - Should revert with `InvalidAmount` (our new fix)
- When exchange rate decreases: `assets` (current) < `redeemRequests[requester]` (original)
  - Should work correctly, deducting current assets
- Partial redemption with exchange rate changes
- Cancel with exchange rate changes
- Multiple requests with different exchange rates

**Test Cases Needed**:

```typescript
describe("Exchange Rate Changes", () => {
  it("should revert when redeeming with increased exchange rate (assets > redeemRequests)");
  it("should allow redeeming with decreased exchange rate");
  it("should handle partial redemption with exchange rate change");
  it("should handle cancel with exchange rate change");
  it("should track multiple requests with different exchange rates correctly");
});
```

### 4. Underflow Protection Tests (New Fixes)

**Status**: ❌ **NO TESTS FOR NEW FIXES**

**What to Test**:

- `redeem()` reverts when `assets > redeemRequests[requester]`
- `redeemFor()` reverts when `assets > redeemRequests[requester]`
- Error message is `InvalidAmount` (not underflow)
- Normal redemption still works when `assets <= redeemRequests[requester]`

**Test Cases Needed**:

```typescript
describe("Underflow Protection", () => {
  it("should revert redeem when assets > redeemRequests[requester]");
  it("should revert redeemFor when assets > redeemRequests[requester]");
  it("should revert with InvalidAmount error (not underflow)");
  it("should allow normal redemption when assets <= redeemRequests");
});
```

### 5. Cancel Accounting Bug Fix Tests

**Status**: ❌ **NO TESTS FOR NEW FIX**

**What to Test**:

- `cancelRedeem()` reverts when `shares > contractShares` (new behavior)
- `cancelRedeemFor()` reverts when `shares > contractShares` (new behavior)
- Error message is `InsufficientBalance`
- Normal cancellation still works when `shares <= contractShares`
- Accounting remains consistent after cancellation

**Test Cases Needed**:

```typescript
describe("Cancel Accounting Fix", () => {
  it("should revert cancelRedeem when shares > contractShares");
  it("should revert cancelRedeemFor when shares > contractShares");
  it("should revert with InsufficientBalance error");
  it("should allow normal cancellation when shares <= contractShares");
  it("should maintain accounting consistency after cancellation");
});
```

### 6. Comprehensive Operator "For" Variant Tests

**Status**: ⚠️ **PARTIALLY TESTED** (some tests exist, but coverage could be better)

**What to Test**:

- `requestRedeemFor`: Operator can request for owner's tokens
- `requestRedeemFor`: Non-operator cannot request
- `requestRedeemFor`: Owner can request for themselves
- `redeemFor`: Operator can redeem for requester
- `redeemFor`: Non-operator cannot redeem
- `redeemFor`: Requester can redeem for themselves
- `cancelRedeemFor`: Operator can cancel for requester
- `cancelRedeemFor`: Non-operator cannot cancel
- `cancelRedeemFor`: Requester can cancel for themselves
- All "For" variants respect epoch delays
- All "For" variants update accounting correctly

**Test Cases Needed**:

```typescript
describe("Operator 'For' Variants", () => {
  describe("requestRedeemFor", () => {
    it("should allow operator to request for owner");
    it("should allow owner to request for themselves");
    it("should revert when non-operator tries to request");
    it("should transfer tokens from owner, not operator");
    it("should create FIFO entry for requester");
  });

  describe("redeemFor", () => {
    it("should allow operator to redeem for requester");
    it("should allow requester to redeem for themselves");
    it("should revert when non-operator tries to redeem");
    it("should send funds to receiver, not operator");
    it("should respect epoch delay");
  });

  describe("cancelRedeemFor", () => {
    it("should allow operator to cancel for requester");
    it("should allow requester to cancel for themselves");
    it("should revert when non-operator tries to cancel");
    it("should return shares to receiver, not operator");
    it("should respect epoch delay");
  });
});
```

---

## 🟡 Medium Priority Tests

### 7. Edge Case Tests

**Status**: ⚠️ **SOME EXIST, BUT COULD BE MORE COMPREHENSIVE**

**What to Test**:

- Multiple partial redemptions
- Redemption after multiple requests
- Cancel after partial redemption
- Request → Cancel → Request again
- Maximum values (uint256 edge cases)
- Very small values (1 wei)
- Multiple operators for same user
- Operator revocation mid-operation

### 8. Access Control Tests

**Status**: ⚠️ **PARTIALLY TESTED**

**What to Test**:

- All functions respect `onlyOwnerOrOperator` checks
- All functions respect `onlyRole(GOV)` checks
- Operator permissions work correctly
- Operator revocation works correctly
- Multiple operators for same user

### 9. Accounting Consistency Tests

**Status**: ⚠️ **PARTIALLY TESTED**

**What to Test**:

- `redeemRequests` matches `totalPendingRequest` sum
- `userEntries[requester].amount` matches `redeemRequests[requester]` initially
- Accounting remains consistent after all operations
- No accounting leaks or stuck funds

---

## 📋 Test Implementation Priority

### Priority 1 (Critical - Security Fixes)

1. ✅ Underflow protection tests (for new fixes)
2. ✅ Cancel accounting bug fix tests (for new fixes)
3. ✅ Granular pause tests (security feature)
4. ✅ `requestRedeemForUser` GOV function tests (access control)

### Priority 2 (Important - Functionality)

5. Exchange rate change tests
6. Comprehensive operator "For" variant tests

### Priority 3 (Nice to Have)

7. Edge case tests
8. Access control comprehensive tests
9. Accounting consistency tests

---

## 📝 Documentation Tasks

### Completed Documentation

- ✅ `MULTIPASS_REVIEW_FINDINGS.md` - Security review findings
- ✅ `REFACTOR_SUMMARY.md` - Refactoring summary
- ✅ `CONTRACT_CLARIFICATIONS.md` - Confusing aspects
- ✅ `UNDERFLOW_ANALYSIS.md` - Underflow analysis
- ✅ `CHANGES_SUMMARY.md` - Changes summary
- ✅ `REFACTOR_REVIEW.md` - Refactoring review
- ✅ `FINAL_SECURITY_REVIEW.md` - Final security review

### Remaining Documentation

- ⚠️ Consider consolidating docs into single comprehensive audit report
- ⚠️ Add inline NatSpec comments for pause function IDs (already done in code)
- ⚠️ Document exchange rate change handling behavior explicitly

---

## 🎯 Summary

### Critical Missing Tests: 5 categories

1. ❌ Granular pause tests (0% coverage)
2. ❌ `requestRedeemForUser` GOV tests (0% coverage)
3. ⚠️ Exchange rate change tests (partial coverage)
4. ❌ Underflow protection tests (0% coverage for new fixes)
5. ❌ Cancel accounting bug fix tests (0% coverage for new fixes)

### Test Files to Create/Update

- `test/v2/core/withdrawQueue.spec.ts` - Add missing test suites
- Consider: `test/v2/core/withdrawQueueGranularPause.spec.ts` - Separate file for pause tests
- Consider: `test/v2/core/withdrawQueueGov.spec.ts` - Separate file for GOV tests

### Estimated Test Cases Needed

- **Granular Pause**: ~10 test cases
- **GOV Function**: ~10 test cases
- **Exchange Rate Changes**: ~5 test cases
- **Underflow Protection**: ~4 test cases
- **Cancel Accounting Fix**: ~5 test cases
- **Operator Variants**: ~15 test cases (comprehensive)

**Total**: ~49 new test cases needed

---

## ✅ Next Steps

1. **Immediate**: Add tests for the two critical security fixes (underflow protection, cancel accounting)
2. **High Priority**: Add granular pause tests and GOV function tests
3. **Medium Priority**: Add exchange rate change tests and comprehensive operator tests
4. **Low Priority**: Add edge case and comprehensive access control tests

---

## Notes

- All existing tests pass (92 test cases in `withdrawQueue.spec.ts`)
- Tests need to be updated if contract behavior changed
- Consider running full test suite after adding new tests
- Consider adding gas optimization tests if needed
- Consider adding fuzzing tests for edge cases
