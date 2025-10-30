# Smart Contract Security Audit - Contract Inventory

## Overview
This document provides a comprehensive inventory of all smart contracts in the SharedStake protocol, including critical security metadata for auditing purposes.

**Audit Date:** $(date)
**Solidity Versions:** 0.8.20, 0.8.7, 0.8.4, 0.7.5, 0.6.11
**Primary Compiler Version:** 0.8.20
**License:** BUSL-1.1, UNLICENSED

---

## Core V2 Contracts (Production)

| Contract Name | Location | Purpose | Upgradeable | Access Control | Critical Functions | Notes |
|--------------|----------|---------|-------------|----------------|-------------------|-------|
| **SgETH** | `contracts/v2/core/SgETH.sol` | ERC20 token representing staked ETH | ❌ No | AccessControl (DEFAULT_ADMIN_ROLE, MINTER) | `addMinter()`, `removeMinter()`, `transferOwnership()` | Inherits from ERC20MintableBurnableByMinter |
| **SharedDepositMinterV2** | `contracts/v2/core/SharedDepositMinterV2.sol` | Mints SgETH for ETH deposits, handles validator deployment | ❌ No | AccessControl (NOR, GOV roles), Pausable, ReentrancyGuard | `deposit()`, `withdraw()`, `batchDepositToEth2()`, `slash()`, `withdrawAdminFee()` | Core contract handling ETH deposits and validator creation |
| **WSGEth** | `contracts/v2/core/WSGEth.sol` | ERC4626 vault wrapping SgETH for auto-compounding | ❌ No | ReentrancyGuard | `deposit()`, `withdraw()`, `redeem()`, `syncRewards()` | Inherits from xERC4626 |
| **WithdrawalQueue** | `contracts/v2/core/WithdrawalQueue.sol` | ERC-7540 inspired withdrawal queue with FIFO epochs | ❌ No | AccessControl (GOV), GranularPause, ReentrancyGuard | `requestRedeem()`, `redeem()`, `cancelRedeem()` | FIFO queue implementation with epoch-based withdrawals |
| **RewardsReceiver** | `contracts/v2/core/RewardsReceiver.sol` | Receives ETH2 staking rewards, routes to deposits or withdrawals | ❌ No | Ownable, YieldDirectorBase | `work()`, `flipState()`, `setDAOFeeSplitter()` | State machine for reward distribution |
| **Rollover** | `contracts/v2/core/Rollover.sol` | Token migration contract (ERC20 to ERC20 redemption) | ❌ No | RedemptionsBase (ReentrancyGuard) | `deposit()`, `redeem()`, `withdraw()` | For migrating from old token to new token |
| **Withdrawals** | `contracts/v2/core/Withdrawals.sol` | ERC20 to ETH redemption contract | ❌ No | RedemptionsBase (ReentrancyGuard) | `deposit()`, `redeem()`, `withdraw()` | Simple redemption from token to ETH |

---

## V2 Library Contracts

| Contract Name | Location | Purpose | Upgradeable | Access Control | Critical Functions | Notes |
|--------------|----------|---------|-------------|----------------|-------------------|-------|
| **ERC20MintableBurnableByMinter** | `contracts/v2/lib/ERC20MintableBurnableByMinter.sol` | Base ERC20 token with mint/burn by minter role | ❌ No | AccessControl (MINTER role) | `mint()`, `burn()`, `burnFrom()` | Inherits ERC20Burnable, ERC20Permit, AccessControl |
| **xERC4626** | `contracts/v2/lib/xERC4626.sol` | ERC4626 variant with linear reward cycles | ❌ No | Internal | `syncRewards()`, `convertToAssets()`, `convertToShares()` | Prevents MEV gaming of exchange rate |
| **FIFOQueue** | `contracts/v2/lib/FIFOQueue.sol` | First-in-first-out queue with epoch-based locking | ❌ No | Internal | `_verifyEpochHasElapsed()`, `_stakeForWithdrawal()`, `_withdraw()` | Abstract base contract |
| **GranularPause** | `contracts/v2/lib/GranularPause.sol` | Granular pause functionality per function | ❌ No | Internal | `_pause(uint16)`, `_unpause(uint16)` | Allows pausing specific functions |
| **OperatorSettable** | `contracts/v2/lib/OperatorSettable.sol` | Operator management for vault operations | ❌ No | Internal | `setOperator()`, `onlyOwnerOrOperator()` | For ERC-7540 operator support |
| **ETH2DepositWithdrawalCredentials** | `contracts/v2/lib/ETH2DepositWithdrawalCredentials.sol` | Manages ETH2 validator withdrawal credentials | ❌ No | Internal | `_batchDeposit()`, `_setWithdrawalCredential()` | Handles validator deposits to ETH2 |
| **YieldDirectorBase** | `contracts/v2/lib/YieldDirectorBase.sol` | Base contract for reward distribution (60/40 split) | ❌ No | Internal | `_convertToSgETHAndTransfer()` | 60% to WSGETH, 40% to feeSplitter |
| **RedemptionsBase** | `contracts/v2/lib/RedemptionsBase.sol` | Base redemption contract | ❌ No | ReentrancyGuard | `deposit()`, `redeem()`, `withdraw()` | Abstract base for token redemption |
| **PaymentSplitter** | `contracts/v2/lib/PaymentSplitter.sol` | Payment splitting utility | ❌ No | AccessControl | Payment distribution | For fee distribution |
| **Errors** | `contracts/v2/lib/Errors.sol` | Custom error definitions | ❌ No | N/A | N/A | Error library |

---

## Periphery Contracts (V2)

| Contract Name | Location | Purpose | Upgradeable | Access Control | Critical Functions | Notes |
|--------------|----------|---------|-------------|----------------|-------------------|-------|
| **FeeCalc** | `contracts/v2/periphery/FeeCalc.sol` | Fee calculation for deposits/withdrawals | ❌ No | Ownable2Step | `processDeposit()`, `processWithdraw()`, `set()` | Configurable fee structure |
| **ETHDepositGuard** | `contracts/v2/periphery/ETHDepositGaurd.sol` | Guard for ETH deposits | ❌ No | TBD | TBD | Need to review |
| **UserDepositHelper** | `contracts/v2/periphery/UserDepositHelper.sol` | Helper contract for user deposits | ❌ No | TBD | TBD | Need to review |
| **Zap** | `contracts/v2/periphery/Zap.sol` | Zap contract for swapping | ❌ No | TBD | TBD | Need to review |

---

## Governance Contracts

| Contract Name | Location | Purpose | Upgradeable | Access Control | Critical Functions | Notes |
|--------------|----------|---------|-------------|----------------|-------------------|-------|
| **MasterChef** | `contracts/governance/MasterChef.sol` | Staking rewards distribution (Sushi-style) | ❌ No | Ownable | `deposit()`, `withdraw()`, `harvest()`, `add()`, `set()` | Fork of Sushi MiniChefV2 |
| **FundDistributor** | `contracts/governance/FundDistributor.sol` | Distributes rewards to users | ✅ Yes (Initializable) | Ownable, onlyRequester | `distributeTo()`, `addRequester()` | Requires initializer call |
| **voteEscrow** | `contracts/governance/voteEscrow.sol` | Voting escrow for token locking | ❌ No | Ownable, ReentrancyGuard | `create_lock()`, `withdraw()`, `emergencyWithdraw()` | Time-locked voting power |
| **TokenMigrator** | `contracts/governance/TokenMigrator.sol` | Token migration with vesting | ❌ No | Ownable | `migrate()`, `releaseTokens()`, `burnAll()` | Includes allowlist/blocklist |
| **SGTv2** | `contracts/governance/SGTv2.sol` | Governance token | ❌ No | TBD | TBD | Need to review |
| **SimpleTimelock** | `contracts/governance/SimpleTimelock.sol` | Timelock for governance | ❌ No | TBD | TBD | Need to review |
| **SimpleVesting** | `contracts/governance/SimpleVesting.sol` | Token vesting contract | ❌ No | TBD | TBD | Need to review |
| **VoteEscrowFactory** | `contracts/governance/VoteEscrowFactory.sol` | Factory for vote escrow contracts | ❌ No | TBD | TBD | Need to review |
| **ComplexRewarderTime** | `contracts/governance/rewarders/ComplexRewarderTime.sol` | Complex rewarder with time-based logic | ❌ No | TBD | TBD | Need to review |
| **testFaucet** | `contracts/governance/testFaucet.sol` | Test faucet (not for production) | ❌ No | TBD | TBD | Test contract only |

---

## Utility Contracts

| Contract Name | Location | Purpose | Upgradeable | Access Control | Critical Functions | Notes |
|--------------|----------|---------|-------------|----------------|-------------------|-------|
| **Allowlist** | `contracts/Allowlist.sol` | Address allowlist | ❌ No | TBD | TBD | Need to review |
| **blocklist** | `contracts/blocklist.sol` | Address blocklist | ❌ No | TBD | TBD | Need to review |
| **AllowlistBase** | `contracts/util/AllowlistBase.sol` | Base allowlist functionality | ✅ Yes | TBD | TBD | Upgradeable base |
| **BlocklistBase** | `contracts/util/BlocklistBase.sol` | Base blocklist functionality | ✅ Yes | TBD | TBD | Upgradeable base |
| **PriceOracleUpgradeable** | `contracts/util/PriceOracleUpgradeable.sol` | Upgradeable price oracle | ✅ Yes | TBD | TBD | Need to review |
| **priceOracle** | `contracts/priceOracle.sol` | Price oracle (non-upgradeable) | ❌ No | TBD | TBD | Need to review |
| **tokenManager** | `contracts/tokenManager.sol` | Token management | ❌ No | TBD | TBD | Need to review |
| **Eth2DepositHelperUpgradeable** | `contracts/util/Eth2DepositHelperUpgradeable.sol` | Upgradeable ETH2 deposit helper | ✅ Yes | TBD | TBD | Need to review |
| **WithdrawQueueUpgradeable** | `contracts/util/WithdrawQueueUpgradeable.sol` | Upgradeable withdrawal queue | ✅ Yes | TBD | TBD | Need to review |
| **MintableBurnableTokenManagerUpgradeable** | `contracts/util/MintableBurnableTokenManagerUpgradeable.sol` | Upgradeable token manager | ✅ Yes | TBD | TBD | Need to review |
| **VaultWithAdminFeeUpgradeable** | `contracts/util/VaultWithAdminFeeUpgradeable.sol` | Upgradeable vault with admin fees | ✅ Yes | TBD | TBD | Need to review |
| **VaultWithSharesAndCapUpgradeable** | `contracts/util/VaultWithSharesAndCapUpgradeable.sol` | Upgradeable vault with cap | ✅ Yes | TBD | TBD | Need to review |
| **UpgradeableSafeContractBase** | `contracts/util/UpgradeableSafeContractBase.sol` | Base for upgradeable contracts | ✅ Yes | TBD | TBD | Safety base contract |
| **TokenTimelock** | `contracts/util/TokenTimelock.sol` | Token timelock | ❌ No | TBD | TBD | Need to review |
| **SingleTokenVestingNonRevocable** | `contracts/util/SingleTokenVestingNonRevocable.sol` | Single token vesting | ❌ No | TBD | TBD | Need to review |
| **OwnershipRolesTemplate** | `contracts/util/OwnershipRolesTemplate.sol` | Ownership roles template | ✅ Yes | TBD | TBD | Need to review |

---

## Legacy/V1 Contracts

| Contract Name | Location | Purpose | Upgradeable | Access Control | Critical Functions | Notes |
|--------------|----------|---------|-------------|----------------|-------------------|-------|
| **GoerliETHRecov** | `contracts/v1/GoerliETHRecov.sol` | Goerli ETH recovery | ❌ No | TBD | TBD | Testnet only |
| **vEth2** | `contracts/vEth2.sol` | Legacy vEth2 token | ❌ No | TBD | TBD | Legacy contract |

---

## Draft Contracts (⚠️ NOT FOR PRODUCTION)

| Contract Name | Location | Purpose | Notes |
|--------------|----------|---------|-------|
| **Controller** | `contracts/drafts/Controller.sol` | Draft controller | ⚠️ DRAFT |
| **sharedDepositEth2Upgradeable** | `contracts/drafts/sharedDepositEth2Upgradeable.sol` | Draft upgradeable deposit | ⚠️ DRAFT |
| **sharedDepositUpgradeable.2.0.0** | `contracts/drafts/sharedDepositUpgradeable.2.0.0.sol` | Draft upgradeable deposit v2 | ⚠️ DRAFT |
| **SharedDepositV2Upgradeable** | `contracts/drafts/SharedDepositV2Upgradeable.sol` | Draft upgradeable deposit | ⚠️ DRAFT |

---

## NFT Contracts

| Contract Name | Location | Purpose | Upgradeable | Access Control | Notes |
|--------------|----------|---------|-------------|----------------|-------|
| **MintableNFTSale** | `contracts/nfts/MintableNFTSale.sol` | NFT sale contract | ❌ No | TBD | Need to review |

---

## Mock Contracts (Test Only)

| Contract Name | Location | Purpose | Notes |
|--------------|----------|---------|-------|
| **DepositContract** | `contracts/mocks/DepositContract.sol` | Mock ETH2 deposit contract | Test only |

---

## Critical Security Points to Audit

### 1. Access Control
- ✅ OpenZeppelin AccessControl used in most contracts
- ⚠️ Check for missing role checks
- ⚠️ Verify ownership transfer mechanisms
- ⚠️ Review initializer vs constructor patterns

### 2. Reentrancy Protection
- ✅ ReentrancyGuard used in critical contracts
- ⚠️ Verify all external calls are protected
- ⚠️ Check CEI (Checks-Effects-Interactions) pattern

### 3. Upgradeable Contracts
- ⚠️ Multiple upgradeable contracts present
- ⚠️ Check for initialization vulnerabilities
- ⚠️ Verify storage layout compatibility
- ⚠️ Review upgrade authorization

### 4. Token Minting/Burning
- ⚠️ Verify minting logic cannot be exploited
- ⚠️ Check burn permissions
- ⚠️ Audit accounting for mint/burn operations

### 5. ETH Handling
- ⚠️ Multiple contracts handle ETH directly
- ⚠️ Verify withdrawal mechanisms
- ⚠️ Check for trapped ETH scenarios

### 6. Governance
- ⚠️ Review MasterChef reward calculations
- ⚠️ Check vote escrow manipulation vectors
- ⚠️ Verify token migrator logic

---

## Key Dependencies

- **OpenZeppelin Contracts:** ^4.8.0 (v4.3.1 for upgradeable)
- **Solmate:** ^6.7.0
- **@fei-protocol/erc4626:** ^0.0.0

---

## Test Coverage

Test files located in `/test/v2/core/`:
- `minter.spec.ts` - SharedDepositMinterV2 tests
- `sgETH.spec.ts` - SgETH token tests
- `wsgETH.spec.ts` - WSGEth vault tests
- `withdrawQueue.spec.ts` - WithdrawalQueue tests
- `rewardsReceiver.spec.ts` - RewardsReceiver tests
- `e2e.spec.ts` - End-to-end integration tests

---

## Next Steps

1. ✅ Contract inventory created
2. 🔄 Audit core v2 contracts for critical vulnerabilities
3. 🔄 Review access control mechanisms
4. 🔄 Audit upgradeable contracts
5. 🔄 Check for reentrancy vulnerabilities
6. 🔄 Review arithmetic operations
7. 🔄 Audit token minting/burning logic
8. 🔄 Review governance contracts
9. 🔄 Check for backdoors and malicious patterns
10. 🔄 Review test coverage
