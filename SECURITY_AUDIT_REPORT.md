# Smart Contract Security Audit Report

## Executive Summary

This audit was conducted to identify potential vulnerabilities and malicious code patterns in the SharedStake protocol contracts, given concerns about potential unauthorized access. The audit covers core v2 contracts, governance contracts, and supporting libraries.

**Audit Date:** December 2024
**Auditor:** Security Review System
**Scope:** All production contracts in `/contracts/v2/core/`, governance contracts, and critical libraries

---

## 🔴 CRITICAL VULNERABILITIES

### 1. CRITICAL: FeeCalc.processDeposit() Returns Uninitialized Values

**Severity:** 🔴 CRITICAL  
**Location:** `contracts/v2/periphery/FeeCalc.sol:44-50`

**Description:**
The `processDeposit()` function does not initialize return values when `config.chargeOnDeposit` is false. This causes both `amt` and `fee` to return 0, resulting in users losing their ETH deposits.

**Vulnerable Code:**
```solidity
function processDeposit(uint256 value, address _sender) external view returns (uint256 amt, uint256 fee) {
    // TODO: semder is currently unsused but can be used later to calculate a fee reduction based on token holdings
    if (config.chargeOnDeposit) {
        fee = (value * adminFee) / BIPS;
        amt = value - fee;
    }
    // BUG: If chargeOnDeposit is false, amt and fee remain 0!
}
```

**Impact:**
- Users deposit ETH but receive 0 sgETH tokens
- Funds are permanently locked in the contract
- Total loss of user deposits

**Attack Scenario:**
1. Admin sets `chargeOnDeposit = false` (or it's set to false by default)
2. User deposits 1 ETH
3. `processDeposit()` returns `(amt=0, fee=0)`
4. `SharedDepositMinterV2._depositAccounting()` uses `value = 0`
5. User receives 0 sgETH tokens but ETH is deposited

**Recommendation:**
```solidity
function processDeposit(uint256 value, address _sender) external view returns (uint256 amt, uint256 fee) {
    if (config.chargeOnDeposit) {
        fee = (value * adminFee) / BIPS;
        amt = value - fee;
    } else {
        fee = 0;
        amt = value;  // FIX: Initialize amt when no fee is charged
    }
}
```

---

### 2. HIGH: WithdrawalQueue Balance Check Race Condition

**Severity:** 🟠 HIGH  
**Location:** `contracts/v2/core/WithdrawalQueue.sol:143-152`

**Description:**
The `redeem()` function checks `MINTER.balance` and then transfers ETH, but the balance can change between the check and the transfer. Additionally, calling `unstakeAndWithdraw()` while the contract still holds ETH can cause accounting issues.

**Vulnerable Code:**
```solidity
uint256 minterBalance = MINTER.balance;
if (assets > minterBalance) {
    uint256 diff = assets - minterBalance;
    payable(MINTER).transfer(diff);
}

// Always burn redeemed tokens
SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
```

**Impact:**
- Potential accounting discrepancies
- Possible double-spending if balance changes occur
- Funds could be transferred incorrectly

**Recommendation:**
- Use `address(MINTER).balance` explicitly
- Add checks to ensure balance consistency
- Consider using a single atomic operation

---

### 3. HIGH: SharedDepositMinterV2 Withdrawal Accounting Issue

**Severity:** 🟠 HIGH  
**Location:** `contracts/v2/core/SharedDepositMinterV2.sol:257-273`

**Description:**
The `_withdrawAccounting()` function checks `address(this).balance < (amount + adminFeeTotal)` before potentially modifying `adminFeeTotal`. If `refundFeesOnWithdraw` is true, `adminFeeTotal` is reduced, but the balance check happens after this reduction, potentially allowing withdrawals when insufficient funds exist.

**Vulnerable Code:**
```solidity
function _withdrawAccounting(uint256 amount) internal returns (uint256) {
    uint256 fee;
    if (address(_feeCalc) != address(0)) {
        (amount, fee) = _feeCalc.processWithdraw(amount, msg.sender);
        if (refundFeesOnWithdraw) {
            adminFeeTotal = adminFeeTotal - fee;  // Modifies adminFeeTotal
        } else {
            adminFeeTotal = adminFeeTotal + fee;
        }
    }
    if (address(this).balance < (amount + adminFeeTotal)) {  // Check happens after modification
        revert AmountTooHigh();
    }
    // ...
}
```

**Impact:**
- Possible withdrawal of funds that should be reserved for admin fees
- Accounting inconsistencies

**Recommendation:**
- Move balance check before fee calculation
- Or use a separate variable to track required reserves

---

## 🟡 MEDIUM SEVERITY ISSUES

### 4. MEDIUM: Access to Internal Constant via Inheritance

**Severity:** 🟡 MEDIUM  
**Location:** `contracts/v2/core/SharedDepositMinterV2.sol:160`

**Description:**
The contract accesses `_depositAmount` which is an internal constant in the parent contract `ETH2DepositWithdrawalCredentials`. While this works due to inheritance, it creates a tight coupling and could break if the parent contract changes.

**Code:**
```solidity
if (address(this).balance < (_depositAmount * pubkeys.length)) {
    revert AmountTooHigh();
}
```

**Impact:**
- Contract breaks if parent contract is modified
- Difficult to maintain

**Recommendation:**
- Use a public constant or getter function
- Or define the constant in the child contract

---

### 5. MEDIUM: RewardsReceiver.work() is Public Payable

**Severity:** 🟡 MEDIUM  
**Location:** `contracts/v2/core/RewardsReceiver.sol:32`

**Description:**
The `work()` function is `external payable` without access control. While it's designed to receive ETH from validator rewards, anyone can call it with arbitrary ETH, potentially causing accounting issues.

**Vulnerable Code:**
```solidity
function work() external payable {
    if (state == State.Deposits) {
        _convertToSgETHAndTransfer();
    } else if (state == State.Withdrawals) {
        WITHDRAWALS.transfer(address(this).balance);
    }
}
```

**Impact:**
- Malicious actors could send ETH and manipulate state
- Potential DoS if state machine logic is abused

**Recommendation:**
- Add access control or at least a check that only expected senders can trigger
- Consider using a whitelist of allowed callers

---

### 6. MEDIUM: Missing Zero Address Checks

**Severity:** 🟡 MEDIUM  
**Location:** Multiple contracts

**Description:**
Several functions accept address parameters without zero address checks:

- `SharedDepositMinterV2.setFeeCalc()` - accepts address(0) which disables fees
- `RewardsReceiver.setDAOFeeSplitter()` - no zero check
- `TokenMigrator.setTarget()` - no zero check in constructor

**Impact:**
- Setting addresses to zero could break functionality
- Accidental misconfiguration

**Recommendation:**
- Add `require(_addr != address(0), "Zero address")` checks
- Document intentional zero address support if needed

---

### 7. MEDIUM: TokenMigrator Logic Issue

**Severity:** 🟡 MEDIUM  
**Location:** `contracts/governance/TokenMigrator.sol:56-70`

**Description:**
The `migrate()` function has unusual logic where users in the allowlist OR blocklist get immediate tokens. Typically, blocklisted addresses should not receive tokens.

**Vulnerable Code:**
```solidity
if (_inAllowlist(msg.sender) || _inBlocklist(msg.sender)) {
    _sendTokens(_value, msg.sender);
    return;
}
```

**Impact:**
- Blocklisted users receive tokens immediately
- Logic appears inverted

**Recommendation:**
- Review business logic - should be `&&` or separate handling?
- If blocklisted users should receive tokens, document why

---

## 🟢 LOW SEVERITY / INFORMATIONAL

### 8. LOW: SafeMath Usage in Solidity 0.8.20+

**Severity:** 🟢 LOW  
**Location:** Multiple contracts using SafeMath

**Description:**
Several contracts use SafeMath (e.g., `RedemptionsBase`, `MasterChef`) but Solidity 0.8.20+ has built-in overflow/underflow protection. SafeMath is redundant but harmless.

**Impact:**
- Unnecessary gas costs
- Code complexity

**Recommendation:**
- Remove SafeMath and use native arithmetic for Solidity 0.8+
- Or document why SafeMath is kept for compatibility

---

### 9. LOW: Missing Events

**Severity:** 🟢 LOW  
**Location:** Various contracts

**Description:**
Some critical state changes don't emit events:
- `SharedDepositMinterV2.migrateShares()` - no event
- `FeeCalc.set()` - no event
- `RewardsReceiver.flipState()` - no event

**Impact:**
- Difficult to track state changes
- Reduced transparency

**Recommendation:**
- Add events for all state-changing functions
- Follow OpenZeppelin event patterns

---

### 10. LOW: Donate Function Accepts ETH Without Minting

**Severity:** 🟢 LOW  
**Location:** `contracts/v2/core/SharedDepositMinterV2.sol:147`

**Description:**
The `donate()` function accepts ETH but doesn't mint tokens or track donations, which could cause accounting issues.

**Code:**
```solidity
function donate() external payable {} // solhint-disable-line
```

**Impact:**
- ETH can be donated without minting shares
- Accounting might become inconsistent

**Recommendation:**
- Document intended behavior
- Or remove if not needed
- Or track donations separately

---

## ✅ SECURITY BEST PRACTICES OBSERVED

1. ✅ **Reentrancy Protection**: Core contracts use `ReentrancyGuard`
2. ✅ **Access Control**: Most contracts use OpenZeppelin's `AccessControl`
3. ✅ **Pausable**: Critical contracts implement pausability
4. ✅ **Safe Transfers**: Using `SafeERC20` and `Address.sendValue()`
5. ✅ **Custom Errors**: Modern error handling for gas efficiency

---

## 🔍 POTENTIAL BACKDOORS REVIEWED

The following were checked for malicious patterns:

1. ✅ **Delegatecall**: No unauthorized delegatecall found
2. ✅ **Selfdestruct**: No selfdestruct found
3. ✅ **Hidden Functions**: All functions are properly declared
4. ✅ **Unexpected External Calls**: Reviewed all external calls
5. ✅ **Privilege Escalation**: Access control appears properly implemented
6. ✅ **Uninitialized Storage**: Initializers appear correct

**No obvious backdoors detected**, but the critical bug in FeeCalc.sol could be exploited if the system is misconfigured.

---

## 📋 TEST COVERAGE ANALYSIS

**Test Files Found:**
- `test/v2/core/minter.spec.ts`
- `test/v2/core/sgETH.spec.ts`
- `test/v2/core/wsgETH.spec.ts`
- `test/v2/core/withdrawQueue.spec.ts`
- `test/v2/core/rewardsReceiver.spec.ts`
- `test/v2/core/e2e.spec.ts`

**Recommendations:**
- Add tests for FeeCalc with `chargeOnDeposit = false`
- Add tests for edge cases in withdrawal queue
- Add tests for access control scenarios
- Add fuzz tests for arithmetic operations

---

## 🎯 PRIORITY RECOMMENDATIONS

### Immediate Actions Required:

1. **URGENT**: Fix `FeeCalc.processDeposit()` to initialize return values
2. **HIGH**: Review and fix withdrawal accounting logic
3. **HIGH**: Add access control to `RewardsReceiver.work()`
4. **MEDIUM**: Add zero address checks throughout
5. **MEDIUM**: Review TokenMigrator allowlist/blocklist logic

### Code Quality Improvements:

1. Add comprehensive events for all state changes
2. Add NatSpec documentation
3. Remove redundant SafeMath usage
4. Add input validation everywhere
5. Improve test coverage

---

## 📊 SUMMARY

| Severity | Count | Status |
|----------|-------|--------|
| 🔴 Critical | 1 | **MUST FIX** |
| 🟠 High | 2 | **SHOULD FIX** |
| 🟡 Medium | 5 | **CONSIDER FIXING** |
| 🟢 Low | 2 | **CONSIDER FIXING** |

**Overall Assessment:**
The codebase follows generally good security practices with proper use of OpenZeppelin libraries, reentrancy guards, and access control. However, **the critical bug in FeeCalc.processDeposit() must be fixed immediately** as it can cause total loss of user funds. The other issues are manageable but should be addressed before mainnet deployment.

**No evidence of malicious backdoors** was found, but the bugs identified could potentially be exploited if not fixed.

---

## DISCLAIMER

This audit is based on static code analysis and manual review. A full security audit should include:
- Dynamic analysis and fuzzing
- Formal verification of critical paths
- Economic analysis of tokenomics
- Integration testing with deployed dependencies
- Review of deployment scripts and upgrade procedures
