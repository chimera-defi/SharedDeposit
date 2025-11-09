# WithdrawalQueue Contract - Confusing Aspects Documentation

## Overview

This document clarifies confusing aspects of the WithdrawalQueue contract to improve understanding and maintainability.

---

## 1. Owner vs Requester Parameter Confusion

### The Issue

The contract uses two separate parameters `owner` and `requester` in `requestRedeem()`, but their relationship and usage is inconsistent:

- **`owner`**: The address that owns the tokens being redeemed (used for `transferFrom`)
- **`requester`**: The address requesting the redemption (used for tracking `redeemRequests`)

### Current Behavior

```solidity
function requestRedeem(uint256 shares, address requester, address owner)
```

- Line 123: `transferFrom(owner, ...)` - Transfers tokens from `owner`
- Line 130: `_stakeForWithdrawal(owner, assets)` - Creates FIFO queue entry for `owner`
- Line 132: `redeemRequests[requester] += assets` - Tracks assets for `requester`

**Problem**: FIFO queue entry is created for `owner`, but `redeem()` accesses it via `requester`. If `owner != requester`, the FIFO queue entry won't exist for `requester`, causing `redeem()` to fail.

### Why This Design?

The separation allows:
- **Operator functionality**: An operator can request redemption on behalf of a token owner
- **Different beneficiaries**: The requester (who initiated) might differ from owner (who owns tokens)

However, the FIFO queue implementation doesn't support this properly.

### Recommendation

**Option 1**: Always use `requester` for FIFO queue operations (recommended):
```solidity
_stakeForWithdrawal(requester, assets); // Use requester consistently
```

**Option 2**: Document that `owner` must equal `requester` and add validation:
```solidity
require(owner == requester, "Owner must equal requester");
```

**Option 3**: Support both by creating entries for both addresses (complex, not recommended)

---

## 2. Assets vs Shares Tracking Confusion

### The Issue

The contract tracks **assets** in `redeemRequests` but operates on **shares** for token transfers. This dual-tracking system can be confusing.

### Why Track Assets?

- **`redeemRequests[requester]`**: Tracks assets (ETH value owed to user)
- **Token operations**: Use shares (actual tokens to burn/transfer)

**Reasoning**:
- Assets represent the **value** that needs to be paid out (can change with exchange rate)
- Shares represent the **tokens** held in the contract (fixed until burned)
- When exchange rate changes, assets change but shares don't

### Example Flow

1. **Request**: User deposits 10 shares when 1 share = 1.1 ETH
   - `redeemRequests[user] = 11 ETH` (assets)
   - Contract holds 10 shares

2. **Exchange rate changes**: 1 share = 1.2 ETH

3. **Redeem**: User redeems 10 shares
   - Converts 10 shares → 12 ETH (assets) using CURRENT rate
   - Deducts 12 ETH from `redeemRequests[user]`
   - Burns 10 shares

**Problem**: If `redeemRequests[user]` was tracking 11 ETH but we deduct 12 ETH, this could cause underflow or accounting mismatch.

### Current Implementation

The contract converts shares to assets at both request time AND redeem time:
- **Request time**: `assets = _convertSharesToAssets(shares)` → stored in `redeemRequests`
- **Redeem time**: `assets = _convertSharesToAssets(shares)` → used for deduction

This means the assets deducted might differ from assets stored if exchange rate changed.

### Recommendation

**Option 1**: Track shares instead of assets (simpler):
```solidity
mapping(address => uint256) public redeemShares; // Track shares
// Convert to assets only when needed for display/validation
```

**Option 2**: Keep current design but ensure consistency:
- Always use the SAME exchange rate for deduction as was used for tracking
- Or recalculate `redeemRequests` when exchange rate changes significantly

**Option 3**: Document that exchange rate changes can cause accounting adjustments (current behavior)

---

## 3. FIFO Queue Design Confusion

### The Issue

The contract is named "WithdrawalQueue" and inherits from "FIFOQueue", but it doesn't implement a true global FIFO queue.

### Current Design

- **Per-user queueing**: Each user has their own `UserEntry` with `amount` and `blocknum`
- **Independent redemption**: Users can redeem independently once their epoch elapses
- **No global ordering**: User A can redeem before User B even if B requested first

### Why "FIFO" in the Name?

The FIFOQueue library comment says:
> "Simple First in first out queue. Uses a system of cascading locks based on the block number. Users need to wait a minimum of epochLength blocks before withdrawing. Users past the epoch boundary can claim, allowing some time for earlier users to claim first"

This suggests a "soft FIFO" where:
- Users must wait an epoch period
- Earlier users get priority (can claim first)
- But no hard enforcement of global ordering

### What It Actually Does

- **Epoch delay**: Users must wait `epochLength` blocks after their request
- **Per-user tracking**: Each user's requests are tracked separately
- **No global queue**: No enforcement that earlier requests must be fulfilled before later ones

### Recommendation

**Option 1**: Rename to clarify it's per-user epoch delay, not global FIFO:
- `EpochDelayedWithdrawal` or `PerUserEpochQueue`

**Option 2**: Implement true global FIFO using `requestsCreated` and `requestsFulfilled`:
```solidity
uint256 nextRequestToProcess;
function redeem(...) {
    require(requestsFulfilled == nextRequestToProcess, "Must process in order");
    // Process request
    requestsFulfilled++;
}
```

**Option 3**: Document current behavior clearly (recommended for now):
- It's a per-user epoch delay system, not a global FIFO queue
- Users can redeem independently once their epoch elapses

---

## 4. CancelRedeem Recalculation Logic

### The Issue

In `cancelRedeem()`, if the contract doesn't have enough shares, the `assets` variable is recalculated, which can cause accounting inconsistencies.

### Current Flow

```solidity
assets = pendingRedeemRequest(requester); // Original: 11 ETH
shares = _convertAssetsToShares(assets);   // Converts to 11 shares
if (shares > contractShares) {              // Only 10 shares available
    shares = contractShares;               // Use 10 shares
    assets = _convertSharesToAssets(shares); // Recalculate: 10 ETH
}
redeemRequests[requester] -= assets;       // Deducts 10 ETH, but tracked 11 ETH
```

### Why This Happens

- User requested redemption when exchange rate was favorable (1 share = 1.1 ETH)
- Exchange rate changed unfavorably (1 share = 1.0 ETH)
- Contract doesn't have enough shares to return
- Recalculates assets based on available shares

### Problem

- `redeemRequests[requester]` was tracking 11 ETH
- Only 10 ETH is deducted
- 1 ETH remains "stuck" in `redeemRequests[requester]` but can't be claimed

### Recommendation

**Option 1**: Track original shares in `requests` mapping:
```solidity
struct Request {
    address requester;
    uint256 shares; // Store original shares
    uint256 assets; // Store original assets
}
// On cancel, return exact shares, deduct exact original assets
```

**Option 2**: Deduct original assets, not recalculated:
```solidity
uint256 originalAssets = pendingRedeemRequest(requester);
// ... recalculation logic ...
redeemRequests[requester] -= originalAssets; // Deduct original, not recalculated
```

**Option 3**: Prevent cancellation if shares insufficient (revert instead of adjusting)

---

## 5. ERC4626 Mode Minter Balance Top-Up

### The Issue

In `redeem()` ERC4626 mode, the contract transfers ETH to the minter if balance is insufficient:

```solidity
if (assets > minterBalance) {
    uint256 diff = assets - minterBalance;
    payable(MINTER).transfer(diff);
}
SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
```

### Why This Exists

The comment says: "This feels suboptimal, but is the easiest way to always burn the token on redemptions"

### Confusing Aspects

1. **Why transfer ETH to minter?**: The minter needs ETH to fulfill the withdrawal
2. **Why not just call unstakeAndWithdraw?**: Because the minter might not have enough ETH
3. **Where does the ETH come from?**: From `address(this).balance` (contract's ETH balance)
4. **Why is this "suboptimal"?**: Because it requires the contract to hold ETH, which could be used more efficiently

### How It Works

1. User redeems shares → needs `assets` ETH
2. Contract checks minter balance
3. If minter doesn't have enough, contract transfers difference
4. Then calls `unstakeAndWithdraw` which burns shares and sends ETH to user

### Recommendation

**Document clearly**:
- The contract must maintain ETH balance for redemptions in ERC4626 mode
- The minter contract is trusted and expected to handle the withdrawal correctly
- This is a design trade-off for simplicity

**Alternative**: Use a more sophisticated mechanism to ensure minter always has sufficient balance, or handle the ETH flow differently.

---

## 6. State Updates Before External Calls

### The Issue

In `redeem()`, state is updated before external calls to the minter:

```solidity
// State updates (lines 170-176)
_withdraw(requester, assets);
redeemRequests[requester] -= assets;
totalPendingRequest -= assets;
totalAssetsOut += assets;
requestsFulfilled++;

// External call (lines 178-189)
payable(MINTER).transfer(diff);
SharedDepositMinterV2(payable(MINTER)).unstakeAndWithdraw(shares, receiver);
```

### Why This Is Confusing

Standard pattern is "checks-effects-interactions" - do external calls last. But here state is updated before external calls.

### Why It's Actually Safe

- **Atomic transactions**: If minter call fails, entire transaction reverts (including state changes)
- **Reentrancy guard**: `nonReentrant` modifier prevents reentrancy attacks
- **No external state reads**: The external call doesn't read contract state

### Recommendation

**Document clearly** that:
- State updates happen before external calls for accounting purposes
- This is safe due to atomic transactions and reentrancy guard
- If minter fails, entire transaction reverts (no partial state)

**Alternative**: Restructure to do external call first, but this might complicate error handling.

---

## 7. Requests Mapping Unused Internally

### The Issue

The contract populates `mapping(uint256 => Request) internal requests;` but never reads from it internally.

### Why It Exists

- **Off-chain indexing**: Events are emitted with `requestId`, allowing off-chain systems to track requests
- **Future functionality**: May be used for future features (e.g., global FIFO queue)
- **Debugging**: Useful for debugging and auditing

### Recommendation

**Document clearly** that:
- The `requests` mapping is for off-chain indexing and future use
- It's not used in contract logic currently
- Events provide the primary way to track requests off-chain

**Alternative**: Remove if truly unused, but keeping it has low gas cost and provides value for indexing.

---

## 8. Granular Pause Function IDs

### The Issue

The pause system uses function IDs (1, 2, 3) but these aren't clearly documented in the contract:

- Function ID 1: `requestRedeem`
- Function ID 2: `redeem`
- Function ID 3: `cancelRedeem`

### Recommendation

**Add constants**:
```solidity
uint16 public constant PAUSE_REQUEST_REDEEM = 1;
uint16 public constant PAUSE_REDEEM = 2;
uint16 public constant PAUSE_CANCEL_REDEEM = 3;
```

**Or document in NatSpec**:
```solidity
/// @param func The function ID to toggle pause state for:
///             1 = requestRedeem, 2 = redeem, 3 = cancelRedeem
```

---

## Summary of Confusing Aspects

1. ✅ **Owner vs Requester**: Inconsistent usage in FIFO queue operations - **FIXED**: Now uses `requester` consistently
2. ✅ **Assets vs Shares**: Dual tracking system can cause accounting mismatches
3. ✅ **FIFO Queue Name**: Misleading - it's per-user epoch delay, not global FIFO
4. ✅ **Cancel Recalculation**: Assets recalculation can leave "stuck" amounts
5. ✅ **Minter Top-Up**: Unclear why ETH is transferred to minter
6. ✅ **State Before External Calls**: Violates checks-effects-interactions pattern (but safe)
7. ✅ **Unused Requests Mapping**: Populated but never read internally
8. ✅ **Pause Function IDs**: Magic numbers without constants

## Changes Made

### 1. Fixed Owner/Requester Mismatch
- **Changed**: `requestRedeem()` now uses `requester` for FIFO queue operations instead of `owner`
- **Reason**: Ensures consistency with `redeem()` which accesses FIFO queue by `requester`
- **Impact**: Fixes potential bug where `owner != requester` would cause `redeem()` to fail

### 2. Added `requestRedeemForUser()` Function
- **New Function**: Allows GOV role to submit redemption requests on behalf of any user
- **Access Control**: Only callable by GOV role (contract owner/governance)
- **Use Cases**: Protocol-initiated redemptions, migrations, emergency situations
- **Behavior**: Same as `requestRedeem()` but bypasses operator checks

## Recommendations Priority

1. ✅ **High**: Fix owner/requester mismatch in FIFO queue - **COMPLETED**
2. **High**: Add explicit validation before subtractions to prevent underflow
3. **Medium**: Document assets vs shares tracking clearly
4. **Medium**: Add constants for pause function IDs
5. **Low**: Consider renaming or documenting FIFO queue behavior
6. **Low**: Document minter top-up logic clearly
