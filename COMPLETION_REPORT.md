# SharedStake Modular-Staking Phase — Completion Report

**Date:** 2026-05-06
**Status:** ✅ Complete and validated

---

## Summary of Changes

### 1. Branding Rename: lido-parity → modular-staking
**Scope:** Contracts, tests, deploy scripts, UI, docs

| Old Path | New Path |
|----------|----------|
| `contracts/v2/lido-parity/` | `contracts/v2/modular-staking/` |
| `test/v2/lido-parity/` | `test/v2/modular-staking/` |
| `deploy/v2-lido-parity/` | `deploy/v2-modular-staking/` |
| `src/components/LidoParity/` | `src/components/ModularStaking/` |
| `src/stores/lidoParity.js` | `src/stores/modularStaking.js` |
| `LidoParityApp.vue` | `ModularStakingApp.vue` |
| `useLidoParityStore` | `useModularStakingStore` |

**Result:** Zero remaining "lido-parity" references in active source code.

---

### 2. Fee Model Reconciliation
**Problem:** `StakingCore` used pure share dilution (pool stays at real ETH backing), but `StakingRouter` inflated `totalPooledEther` by fee amount.

**Fix:** Removed pool inflation in `StakingRouter._distributeFees`. Both paths now use pure share dilution:
- Fees captured by minting shares to treasury/operator
- Pool stays at actual buffered + beacon ETH
- Updated 4 test files to match invariant

---

### 3. Missing Tests Added

| Test File | Coverage |
|-----------|----------|
| `test/v2/modular-staking/lidoPriceOracle.spec.ts` | Deployment, getEthValue, getLstValue, round-trip, lastUpdated, zero-address revert |
| `test/v2/modular-staking/dvtModule.spec.ts` | moduleType=DVT_VALIDATOR, inheritance from ValidatorModule, pause, router integration |
| `test/v2/modular-staking/fuzz.spec.ts` | 19 edge-case / invariant tests for ShareMath, FeeController, StakingCore, WithdrawalQueueV2 |

**Total test count:** 288 passing (was 256)

---

### 4. Security Review

**Tool:** Slither + manual review
**Scope:** All `v2/modular-staking/` contracts
**Result:**
- 0 Critical issues
- 0 High severity issues
- 0 Medium severity issues
- 8 Low/Info findings — all reviewed:
  - Reentrancy warnings: false positives (trusted internal contracts + `nonReentrant` guards)
  - WstToken transfer return values: ignored because ST_TOKEN is own contract (always true)
  - FeeController division ordering: standard fee math, sub-wei precision loss acceptable
  - Local variable initialization: Solidity auto-initializes to 0
  - Naming shadow: `paused` return parameter in `StakingRouter.modules`

**Document:** `SharedDeposit/SECURITY_REVIEW.md`

---

### 5. Defunct Code Deleted

| Deleted File | Reason |
|-------------|--------|
| `contracts/drafts/Controller.sol` | 0 references, old draft |
| `contracts/drafts/sharedDepositEth2Upgradeable.sol` | 0 references, old draft |
| `contracts/drafts/sharedDepositUpgradeable.2.0.0.sol` | 0 references, old draft |
| `contracts/drafts/SharedDepositV2Upgradeable.sol` | 0 references, old draft |
| `contracts/v1/GoerliETHRecov.sol` | Goerli dead, 0 active refs |
| `scripts/v2/goerli_eth_recov.js` | Goerli-specific, obsolete |

---

### 6. UI Validation

| Check | Result |
|-------|--------|
| Type-check | ✅ Pass |
| Build | ✅ Pass |
| Pre-commit hook (lint + type-check + build) | ✅ Pass |
| No orphaned references | ✅ Verified |

---

### 7. Known Gaps (Documented, Not Blockers)

| Gap | Priority | Status |
|-----|----------|--------|
| DVTModule is a skeleton (extends ValidatorModule, no cluster logic) | Medium | Documented in ASSESSMENT.md |
| No deploy script for DVTModule | Medium | Ready to add when cluster logic built |
| QuorumOracleAdapter exists but default deploy uses single-submitter | Medium | Manual switch for mainnet |
| No dedicated e2e test for modular-staking UI flow | Low | Old v2/core e2e still works |
| InstitutionalPolicyRegistry not auto-wired | Low | Optional feature |

---

### 8. Rollout Plan (From ASSESSMENT.md)

**Phase 0 (Testnet):**
- All 288 tests passing
- Use QuorumOracleAdapter with ≥3 submitters

**Phase 1 (Soft Launch Mainnet):**
- ValidatorModule mintCap = 320 ETH (10 validators)
- LSTWrapModule mintCap = 100 ETH
- maxDeltaBps = 500 (5%)
- maxSlashBps = 250 (2.5%)
- Bunker mode default

**Phase 2 (Scale):**
- Raise caps gradually: 960 → 3200 → unlimited
- Relax maxDeltaBps to 1000 (10%)
- Add DVTModule with dedicated cap

**Phase 3 (Decentralize):**
- Transfer GOV to community multisig
- Enable turbo mode default

---

### 9. Commits

**SharedDeposit:**
- `e239a55` fix(lido-parity): reconcile fee model
- `273405c` refactor(modular-staking): complete rename, tests, security, cleanup

**UI:**
- `518eedb` refactor(ui): rename LidoParity → ModularStaking

---

**Next recommended steps:**
1. Update README.md to document the modular-staking phase
2. Add `011_dvtModule.ts` deploy script (minimal, ready for Phase 2)
3. Wire QuorumOracleAdapter as default oracle path for mainnet
4. Add keeper monitoring/alerting integration
