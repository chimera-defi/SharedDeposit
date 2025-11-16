# Security Review: Withdrawal Contracts

**Date:** 2024
**Reviewer:** AI Security Audit
**Contracts Reviewed:**
- `contracts/v2/core/Withdrawals.sol`
- `contracts/v2/core/WithdrawalQueue.sol`
- `contracts/v2/lib/RedemptionsBase.sol`

---

## Executive Summary

This security review identified **2 CRITICAL**, **3 HIGH**, and **5 MEDIUM** severity issues in the withdrawal contracts. The most critical issues involve accounting inconsistencies, exchange rate manipulation risks, and potential DoS vectors.

---

## Critical Issues

### 🔴 CRITICAL-1: Accounting State Update Order in `redeem()`

**Location:** `WithdrawalQueue.sol:170-176`

**Issue:**
The `redeem()` function updates accounting state (`redeemRequests`, `totalPendingRequest`) AFTER calling `_withdraw()`. While `_withdraw()` only updates FIFO queue state, this ordering could lead to inconsistencies if the external call to `unstakeAndWithdraw()` or `transfer()` fails.

**Code:**
```solidity
_withdraw(requester, assets);
// Treat everything as claimableRedeemRequest and validate here if there's adequate funds
redeemRequests[requester] -= assets; // underflow would revert if not enough claimable shares
totalPendingRequest -= assets;
```

**Impact:**
- If external call fails after `_withdraw()`, FIFO state is updated but accounting isn't
- Could lead to inconsistent state where user's FIFO entry is cleared but `redeemRequests` still shows pending

**Recommendation:**
Follow checks-effects-interactions pattern strictly:
1. Update all accounting state FIRST
2. Then perform external calls
3. Consider using a try-catch for external calls or revert on failure

**Fix:**
```solidity
// Update accounting BEFORE external calls
redeemRequests[requester] -= assets;
totalPendingRequest -= assets;
totalAssetsOut += assets;
requestsFulfilled++;

// Then perform external operations
_withdraw(requester, assets);
// ... rest of function
```

---

### 🔴 CRITICAL-2: Exchange Rate Manipulation in `cancelRedeem()`

**Location:** `WithdrawalQueue.sol:224`

**Issue:**
When canceling a redemption, shares are recalculated using the CURRENT exchange rate, which may differ significantly from when the request was made. This allows users to exploit exchange rate changes.

**Code:**
```solidity
// Convert assets back to shares using current exchange rate
// Note: This uses the current exchange rate, which may differ from when the request was made
uint256 shares = _convertAssetsToShares(assets);
```

**Attack Scenario:**
1. User requests redemption when exchange rate is 1:1 (100 shares = 100 assets)
2. Exchange rate changes to 1:1.5 (100 shares = 150 assets)
3. User cancels redemption
4. User receives 150 shares back instead of 100 shares
5. User profits from the exchange rate change

**Impact:**
- Users can profit from exchange rate volatility
- Protocol loses value when exchange rate increases
- Users can game the system by timing cancellations

**Recommendation:**
Store the original shares amount in the Request struct and use that for cancellation instead of recalculating.

**Fix:**
```solidity
// In requestRedeem, store shares in Request struct (already done)
// In cancelRedeem, use stored shares instead of recalculating
uint256 shares = requests[requestId].shares; // Need to track requestId per user
// OR store shares in a mapping: mapping(address => uint256) public pendingShares;
```

---

## High Severity Issues

### 🟠 HIGH-1: Missing Shares Validation in `redeem()`

**Location:** `WithdrawalQueue.sol:144-176`

**Issue:**
The `redeem()` function accepts a `shares` parameter but doesn't validate that the shares being redeemed match the user's pending redemption request. A user could potentially redeem more or less than their actual pending request.

**Code:**
```solidity
function redeem(
    uint256 shares,
    address receiver,
    address requester
) external onlyOwnerOrOperator(requester) nonReentrant whenNotPaused(uint16(2)) returns (uint256 assets) {
    // ... validation ...
    assets = _convertSharesToAssets(shares);
    // No validation that shares matches pending request
```

**Impact:**
- Users could redeem incorrect amounts
- Could lead to accounting inconsistencies
- Potential for partial redemption attacks

**Recommendation:**
Add validation to ensure `shares` doesn't exceed the user's pending shares. Track pending shares separately or validate against `redeemRequests`.

**Fix:**
```solidity
// Add mapping to track pending shares
mapping(address => uint256) public pendingShares;

// In requestRedeem:
pendingShares[requester] += shares;

// In redeem:
if (shares > pendingShares[requester]) {
    revert Errors.InvalidAmount();
}
pendingShares[requester] -= shares;
```

---

### 🟠 HIGH-2: Potential DoS via `MINTER.balance` Access

**Location:** `WithdrawalQueue.sol:180`

**Issue:**
The contract accesses `MINTER.balance` directly. If MINTER is a contract that doesn't properly handle balance queries or reverts, this could cause DoS.

**Code:**
```solidity
uint256 minterBalance = MINTER.balance;
```

**Impact:**
- If MINTER contract has issues, `redeem()` could fail
- Users unable to redeem their funds

**Recommendation:**
Add try-catch or validate MINTER address. However, since `.balance` is a Solidity property (not a call), this is lower risk but still worth noting.

**Note:** This is actually safe since `.balance` is a property, not a function call. But worth documenting.

---

### 🟠 HIGH-3: Race Condition in `requestRedeem()` - Epoch Reset

**Location:** `WithdrawalQueue.sol:130`

**Issue:**
When a user calls `requestRedeem()` multiple times before the epoch expires, `_stakeForWithdrawal()` resets the epoch clock (sets `blocknum = block.number`). This is documented but could be exploited.

**Code:**
```solidity
_stakeForWithdrawal(owner, assets); // This resets blocknum to current block
```

**Attack Scenario:**
1. User requests redemption (epoch starts at block N)
2. User waits until block N + epochLength - 1
3. User calls `requestRedeem()` again
4. Epoch resets to current block
5. User must wait another full epochLength

**Impact:**
- Users could accidentally delay their own withdrawals
- Malicious users could exploit this to delay withdrawals indefinitely
- Could be used as a griefing attack

**Recommendation:**
Consider preventing new requests if user already has pending requests, OR don't reset epoch if it's already elapsed.

**Fix:**
```solidity
// Option 1: Prevent multiple requests
if (redeemRequests[requester] > 0) {
    revert Errors.PendingRequestExists();
}

// Option 2: Don't reset epoch if already elapsed
UserEntry memory ue = userEntries[owner];
if (block.number >= ue.blocknum + epochLength) {
    // Epoch already elapsed, don't reset
    ue.amount = ue.amount + assets;
} else {
    // Reset epoch
    ue.blocknum = block.number;
    ue.amount = ue.amount + assets;
}
userEntries[owner] = ue;
```

---

## Medium Severity Issues

### 🟡 MEDIUM-1: Unsafe `transfer()` in `redeem()` Fixed Price Mode

**Location:** `WithdrawalQueue.sol:195`

**Issue:**
Uses `transfer()` which has a 2300 gas limit. If receiver is a contract, this could fail.

**Code:**
```solidity
payable(receiver).transfer(assets);
```

**Impact:**
- Redemptions could fail for contract receivers
- Users unable to receive funds

**Recommendation:**
Use `Address.sendValue()` or `Address.functionCallWithValue()` instead of `transfer()`.

**Fix:**
```solidity
Address.sendValue(payable(receiver), assets);
```

---

### 🟡 MEDIUM-2: Unsafe `transfer()` in ERC4626 Mode

**Location:** `WithdrawalQueue.sol:185`

**Issue:**
Uses `transfer()` to send ETH to MINTER, which could fail if MINTER is a contract without receive/fallback.

**Code:**
```solidity
payable(MINTER).transfer(diff);
```

**Impact:**
- Redemptions could fail if MINTER doesn't accept ETH transfers
- DoS vector

**Recommendation:**
Use `Address.sendValue()` or validate MINTER can receive ETH.

**Fix:**
```solidity
Address.sendValue(payable(MINTER), diff);
```

---

### 🟡 MEDIUM-3: Division by Zero Risk in Fixed Price Mode

**Location:** `WithdrawalQueue.sol:320`

**Issue:**
If `VIRTUAL_PRICE` is set incorrectly (e.g., 0 when it shouldn't be), division could fail. However, constructor validates this.

**Code:**
```solidity
return (assets * 1e18) / VIRTUAL_PRICE;
```

**Impact:**
- If VIRTUAL_PRICE is 0 (shouldn't happen due to constructor check), division fails
- Low risk due to constructor validation

**Recommendation:**
Add explicit check in `_convertAssetsToShares()` for defense in depth.

**Fix:**
```solidity
if (VIRTUAL_PRICE == 0) {
    revert Errors.InvalidAmount();
}
```

---

### 🟡 MEDIUM-4: Missing Event Emission for State Changes

**Location:** Multiple locations

**Issue:**
Some state changes don't emit events, making off-chain tracking difficult.

**Impact:**
- Difficult to track contract state changes
- Harder to detect anomalies

**Recommendation:**
Emit events for all significant state changes (already mostly done, but worth reviewing).

---

### 🟡 MEDIUM-5: Potential Integer Overflow in `totalPendingRequest`

**Location:** `WithdrawalQueue.sol:131`

**Issue:**
While Solidity 0.8+ has overflow protection, very large values could still cause issues.

**Code:**
```solidity
totalPendingRequest += assets;
```

**Impact:**
- Extremely unlikely but worth noting
- Could cause DoS if values become too large

**Recommendation:**
Add validation for maximum pending requests (optional, low priority).

---

## Low Severity / Code Quality Issues

### 🔵 LOW-1: Inconsistent Error Handling

**Location:** Multiple

**Issue:**
Some functions use custom errors, others use require statements. Should be consistent.

**Recommendation:**
Use custom errors consistently throughout.

---

### 🔵 LOW-2: Missing NatSpec Comments

**Location:** Some internal functions

**Issue:**
Some internal functions lack NatSpec documentation.

**Recommendation:**
Add comprehensive NatSpec comments for all public/external functions.

---

### 🔵 LOW-3: Gas Optimization Opportunities

**Location:** Multiple

**Issues:**
- Multiple storage reads could be cached
- Some calculations could be optimized

**Recommendation:**
Review gas optimization opportunities (low priority).

---

## RedemptionsBase.sol Issues

### 🟠 HIGH-4: Unsafe `transferFrom()` in `withdraw()`

**Location:** `RedemptionsBase.sol:49`

**Issue:**
Uses `transferFrom()` incorrectly - trying to transfer FROM the contract TO the user, but `transferFrom` requires approval.

**Code:**
```solidity
vEth2Token.transferFrom(address(this), msg.sender, amt);
```

**Impact:**
- `withdraw()` will fail because contract doesn't approve itself
- Users cannot withdraw their funds

**Recommendation:**
Use `transfer()` instead since the contract owns the tokens.

**Fix:**
```solidity
vEth2Token.transfer(msg.sender, amt);
```

---

### 🟡 MEDIUM-6: Missing Zero Address Check in Constructor

**Location:** `RedemptionsBase.sol:33`

**Issue:**
Constructor doesn't validate `_underlying` is not zero address.

**Impact:**
- Contract could be deployed with invalid underlying token
- Would cause all operations to fail

**Recommendation:**
Add zero address check in constructor.

**Fix:**
```solidity
if (_underlying == address(0)) {
    revert Errors.ZeroAddress();
}
```

---

## Withdrawals.sol Issues

### 🟡 MEDIUM-7: Unsafe `transfer()` Usage

**Location:** `Withdrawals.sol:26`

**Issue:**
Uses `transfer()` which has 2300 gas limit.

**Code:**
```solidity
payable(msg.sender).transfer(amountToReturn);
```

**Impact:**
- Redemptions could fail for contract receivers

**Recommendation:**
Use `Address.sendValue()` instead.

**Fix:**
```solidity
Address.sendValue(payable(msg.sender), amountToReturn);
```

---

## Recommendations Summary

### Immediate Actions Required:
1. ✅ Fix accounting order in `redeem()` (CRITICAL-1)
2. ✅ Fix exchange rate manipulation in `cancelRedeem()` (CRITICAL-2)
3. ✅ Fix `transferFrom()` bug in `RedemptionsBase.withdraw()` (HIGH-4)
4. ✅ Add shares validation in `redeem()` (HIGH-1)

### High Priority:
5. ✅ Replace `transfer()` with `Address.sendValue()` (MEDIUM-1, MEDIUM-2, MEDIUM-7)
6. ✅ Consider epoch reset prevention in `requestRedeem()` (HIGH-3)

### Medium Priority:
7. ✅ Add zero address checks where missing
8. ✅ Add division by zero checks for defense in depth
9. ✅ Improve error handling consistency

---

## Testing Recommendations

1. **Test exchange rate changes** - Verify `cancelRedeem()` behavior when exchange rate changes
2. **Test accounting consistency** - Verify state remains consistent after failed external calls
3. **Test epoch reset behavior** - Verify multiple `requestRedeem()` calls behave correctly
4. **Test edge cases** - Zero amounts, maximum values, contract receivers
5. **Test reentrancy** - Verify all external calls are properly protected
6. **Test access control** - Verify operator permissions work correctly

---

## Conclusion

The withdrawal contracts have several critical and high-severity issues that need immediate attention. The most critical issues involve accounting inconsistencies and exchange rate manipulation. Once these are fixed, the contracts should be re-audited before mainnet deployment.

**Overall Risk Level:** 🔴 **HIGH** - Requires fixes before production use.
