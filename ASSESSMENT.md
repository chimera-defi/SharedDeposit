# SharedStake V2 Lido-Parity / Modular Phase — Comprehensive Assessment

**Date:** 2026-05-06
**Scope:** `contracts/v2/lido-parity/`, `contracts/v2/modular/`, deploy scripts, tests, keepers, runbooks

---

## 1. Fixes Applied Today

### Fee Model Reconciliation (StakingCore ↔ StakingRouter)
**Problem:** `StakingCore._distributeFees` had an uncommitted fix that removed pool inflation, but `StakingRouter._distributeFees` still inflated `totalPooledEther` by the fee amount. Tests on both sides expected different behaviors.

**Fix:**
- `StakingCore.sol` — confirmed pure share dilution (no pool inflation). Pool stays at real ETH backing.
- `StakingRouter.sol` — aligned with StakingCore. Removed `ST_TOKEN.setTotalPooledEther(totalPooledAfterFees)` line. Fee recipients are paid via share dilution only.
- `stakingCore.spec.ts`, `e2e.spec.ts` — updated expectations from 10.55 → 10.5.
- `stakingRouter.spec.ts` — updated `totalPooledAfterFees` expectation from 32.55 → 32.5.
- `e2e-router.spec.ts` — changed `gt(32.5)` to `equal(32.5)`.

**Result:** All 256 tests passing.

---

## 2. Architecture Overview

### Two staking surfaces coexist:

| Surface | Entry Contract | MINTER on StToken | Oracle Path | Fee Model |
|---------|---------------|-------------------|-------------|-----------|
| **Phase 1 (legacy)** | `StakingCore` | StakingCore | `OracleAdapter` → StakingCore | Pure dilution ✅ |
| **Phase 2 (modular)** | `StakingRouter` | StakingRouter | `OracleAdapter`/`QuorumOracleAdapter` → `ValidatorModule` → Router | Pure dilution ✅ (just fixed) |

### Module types supported:
- `ValidatorModule` — solo validators (buffer ETH → beacon deposit → oracle reports)
- `DVTModule` — placeholder for Obol/SSV (extends ValidatorModule, overrides `moduleType()`)
- `LSTWrapModule` — accept stETH/rETH/etc, mint stToken backed by LST oracle price

### Token stack:
- `StToken` — rebasing stETH-like token (shares under the hood)
- `WstToken` — non-rebasing wrapped version (fixed shares)
- `WithdrawalQueueV2` — 3-step lifecycle: request → finalize → claim

---

## 3. Gaps & Incomplete Work

### 🔴 Critical Gaps

#### 3.1 DVTModule is a Skeleton
**File:** `contracts/v2/lido-parity/modules/DVTModule.sol`
- Only overrides `moduleType()` to return `keccak256("DVT_VALIDATOR")`.
- No cluster coordinator hooks, no threshold-signature pre-flight, no operator whitelist.
- **No deploy script** for DVTModule.
- **No tests** for DVTModule.
- **Verdict:** Not production-ready for DVT. Needs Phase 2 work.

#### 3.2 No Deploy Script for DVTModule
The deploy pipeline (`deploy/v2-lido-parity/`) has scripts for StToken, WstToken, FeeController, StakingCore, WithdrawalQueue, OracleAdapter, StakingRouter, ValidatorModule, LSTWrapModule — but **no DVTModule deploy script**.

#### 3.3 Missing Tests
- **LidoPriceOracle** — no dedicated test file.
- **DVTModule** — no test file.
- These are the only two contracts in `v2/lido-parity/` without coverage.

#### 3.4 OracleAdapter lacks Quorum (Documented Phase 2 Gap)
`OracleAdapter.sol` is single-submitter. `QuorumOracleAdapter.sol` exists but there is **no deploy script that wires QuorumOracleAdapter** as the active oracle path. The default deploy (006) uses single-submitter OracleAdapter.

**Risk:** Single-point-of-failure on oracle. For mainnet, QuorumOracleAdapter should be the active path.

#### 3.5 No WstToken Deploy Integration
`002_wstToken.ts` deploys WstToken but **the deploy pipeline does not wire WstToken to StToken** (setStToken call is manual). The deploy script exists but may not be fully wired in the sequence.

### 🟡 Medium Gaps

#### 3.6 Keeper Scripts are Minimal but Functional
- `depositSweep.ts` — handles ONE validator per run. No multi-validator batching (`VALIDATORS_FILE` mentioned but not implemented).
- `oracleReporter.ts` — single-submitter only. No quorum coordination.
- `withdrawalFinalizer.ts` — solid, has lock file, batching, retry logic.

#### 3.7 No Inflow Limiter Tests
`StakingRouter` has `setModuleInflowLimit()` and `_consumeInflow()` but I didn't find dedicated adversarial tests for the inflow limiter.

#### 3.8 InstitutionalPolicyRegistry Not Wired by Default
`StakingRouter.setPolicyRegistry()` exists but no deploy script sets it. `modulePolicyId` is empty by default. Fine for MVP but needs explicit decision for mainnet.

#### 3.9 No Emergency Recovery/Migration Path
The contracts have `GranularPause` and `emergencyPauseAll()` but there is **no documented migration path** for recovering from catastrophic module failure (e.g., a compromised ValidatorModule that has been granted MINTER via Router). If a module is compromised, GOV can pause it, but there's no way to "unwind" a module's ETH attribution without a full governance proposal and manual rebalancing.

### 🟢 Low / Documentation Gaps

#### 3.10 README Outdated
Root `README.md` talks about "V2 core" but doesn't mention the lido-parity / modular phase at all. The V3 wishlist section is from 2023 and doesn't reflect the current modular architecture.

#### 3.11 `contracts/v2/core/README.md` Only Covers Old Core
Doesn't mention the lido-parity contracts, StakingRouter, or modular design.

#### 3.12 v2/core Contracts Not Integrated with v2/lido-parity
There are two separate contract worlds:
- `v2/core/` — old sgETH, SharedDepositMinterV2, WSGEth, RewardsReceiver, WithdrawalQueue
- `v2/lido-parity/` — new StToken, StakingCore, StakingRouter, etc.

These are **not connected**. The lido-parity contracts use `StToken` (not `sgETH`). The old core uses `sgETH`. This appears to be an intentional migration path, but it needs explicit documentation: "v2/core is production mainnet, v2/lido-parity is the next phase under test."

---

## 4. DVT & Solo Staker Support

### Solo Stakers ✅
Fully supported via `ValidatorModule`:
- Buffer ETH in module
- `depositToBeaconChain()` pushes 32 ETH to beacon deposit contract
- Oracle reports balance → Router rebases StToken
- Mint caps per module: `registerModule(moduleId, addr, mintCapEth)`
- Inflow rate limiter: `setModuleInflowLimit()`

**How to add a solo staker module:**
1. Deploy `ValidatorModule` with unique `moduleId` and `beaconDepositContract`
2. Router registers it: `registerModule(moduleId, moduleAddr, mintCapEth)`
3. Set as default or users call `submitToModule(moduleId)`

### DVT (Obol, SSV) ⚠️
**Not production-ready.**
- `DVTModule.sol` exists but is a thin inheritance of `ValidatorModule`.
- No cluster-specific logic (operator whitelisting, threshold signature validation, cluster lifecycle).
- The comment explicitly says: "reserve this contract as the integration point for cluster-coordinator hooks in Phase 2."

**Path to DVT support:**
1. Extend `DVTModule` with:
   - `registerCluster(bytes32 clusterId, address[] operators, uint256 threshold)`
   - `depositToBeaconChain()` that validates threshold signatures before pushing to beacon
   - Per-cluster accounting (or use the module's existing buffer/beacon balance)
2. Off-chain: integrate Obol/SSV SDK for cluster creation and key generation
3. Add deploy script `011_dvtModule.ts`
4. Add tests `dvtModule.spec.ts`

---

## 5. Safety Features Assessment

### ✅ Strong Safety Features Present

| Feature | Where | How It Works |
|---------|-------|--------------|
| **Per-module mint caps** | `StakingRouter.registerModule()` | `mintCapEth` limits total ETH per module. 0 = unlimited. |
| **Per-module inflow rate limits** | `StakingRouter.setModuleInflowLimit()` | Window-based: X ETH per Y seconds per module. |
| **Beacon gain sanity checks** | `StakingRouter.maxDeltaBps` (default 10%) | Reverts if beacon balance grows >10% per report. |
| **Beacon baseline initialization** | `StakingRouter._enforceBeaconGainSanity()` | Requires `notifyBeaconDeposit` before first positive report (prevents counting principal as rewards). |
| **Slash guard** | `OracleAdapter.maxSlashBps` (default 5%) | Reverts if balance drops >5% per report. GOV can temporarily raise. |
| **Stale report guard** | `OracleAdapter.maxStalenessSeconds` (6h) | Reverts if report timestamp is too old. |
| **Granular pause** | All major contracts | Per-function pause via `GranularPause` lib. GUARDIAN pauses, GOV unpauses. |
| **Emergency pause all** | `StakingRouter.emergencyPauseAll()` | Pauses submit + every registered module in one tx. |
| **Bunker mode** | `WithdrawalQueueV2` | Oracle-controlled mode that limits finalize batch size and enforces minimum request age (e.g., 1 day). Prevents mass exits during distress. |
| **Turbo mode** | `WithdrawalQueueV2` | Normal fast finalization when oracle says everything is fine. |
| **Access control** | All contracts | OZ AccessControl with GOV, GUARDIAN, ORACLE, NODE_OPERATOR, SUBMITTER roles. |
| **ReentrancyGuard** | All entry points | `nonReentrant` on submit, finalize, claim, wrap, unwrap. |
| **Quorum oracle adapter** | `QuorumOracleAdapter.sol` | M-of-N submitter consensus before forwarding report. |
| **Institutional policy** | `InstitutionalPolicyRegistry.sol` + Router | Optional allowlist per module for KYC/accredited-investor checks. |
| **Lock file in keeper** | `withdrawalFinalizer.ts` | Prevents multiple keeper instances from double-finalizing. |
| **Explicit gas limits** | All keepers | Avoids estimation failures under congestion. |
| **Retry + backoff** | All keepers | Exponential backoff on RPC/tx failures. |
| **Beacon API timeout** | `oracleReporter.ts` | 10s timeout prevents hung beacon nodes from stalling keeper. |

### ⚠️ Safety Gaps

| Gap | Risk | Mitigation Needed |
|-----|------|-------------------|
| **Single submitter oracle is default** | Compromised submitter key can push bad reports | Deploy `QuorumOracleAdapter` with ≥3 submitters for mainnet |
| **No circuit breaker on total pooled ETH** | If all modules are compromised simultaneously, totalPooledEther could be manipulated | Add a `maxTotalPooledEther` cap or a global sanity bound |
| **No slashing event recovery playbook** | If validators are slashed >5%, the system freezes on stale data until GOV raises `maxSlashBps` | Document the exact response sequence in the runbook |
| **No automated guardian alerts** | Pauses require manual GUARDIAN action | Integrate keeper with monitoring/alerting (e.g., PagerDuty, Telegram) |
| **No deposit sweep batching** | `depositSweep.ts` handles one validator at a time | For >10 validators, this is inefficient. Add multi-validator batching. |
| **DVTModule has no safety differentiation** | DVT and solo modules share the same safety model | When DVT is built, consider lower `maxDeltaBps` for DVT clusters (more conservative) |

---

## 6. Rollout & Gradual Raise Plan

### Recommended Mainnet Rollout (Phased)

#### Phase 0: Pre-Launch (Testnet)
- [x] All contracts deployed on Sepolia/Goerli
- [x] Tests passing (256/256)
- [ ] **Add:** QuorumOracleAdapter as active oracle (not single-submitter)
- [ ] **Add:** ≥3 independent submitter keys
- [ ] **Add:** DVTModule deploy script + basic tests (even if Phase 2 features)
- [ ] **Add:** LidoPriceOracle tests
- [ ] **Add:** Inflow limiter adversarial tests
- [ ] **Run:** Full keeper dry-run on testnet (deposit sweep → oracle report → finalize → claim)

#### Phase 1: Soft Launch (Mainnet)
1. **Deploy with low caps:**
   - `ValidatorModule` mintCapEth = 320 ETH (10 validators)
   - `LSTWrapModule` mintCapEth = 100 ETH
   - `maxDeltaBps` = 500 (5%, more conservative than default 10%)
   - `maxSlashBps` = 250 (2.5%)
2. **Wire QuorumOracleAdapter** with 3 submitters, quorum = 2
3. **Set bunker mode as default** (`WithdrawalQueueV2`): `bunkerMaxRequestsPerFinalize = 8`, `bunkerMinRequestAge = 2 days`
4. **Run with GUARDIAN = fast-response multisig** (e.g., 2-of-3 with 1-hour response SLA)
5. **GOV = timelocked multisig** (e.g., 3-of-5 with 48h timelock)

#### Phase 2: Scale (After 30 Days of Stable Operation)
1. **Raise caps gradually:**
   - Week 4: ValidatorModule mintCap → 960 ETH (30 validators)
   - Week 8: ValidatorModule mintCap → 3200 ETH (100 validators)
   - Week 12: ValidatorModule mintCap → unlimited (0)
2. **Raise `maxDeltaBps` → 1000** (10%, standard) if no anomalies
3. **Lower `bunkerMinRequestAge` → 1 day** if withdrawal queue is healthy
4. **Add DVTModule** with dedicated mint cap (e.g., 160 ETH initial)
5. **Add LSTWrapModule** for additional LSTs beyond stETH (e.g., rETH, cbETH)

#### Phase 3: Full Decentralization
1. **Transfer GOV to large community multisig** (e.g., 5-of-9 with partners)
2. **Add institutional policy registry** for regulated use-cases
3. **Enable turbo mode as default** (bunker only during distress)
4. **Consider adding slashing insurance** or risk tranching

### Cap Controls Available

```solidity
// Per-module mint cap (risk budget)
router.registerModule(moduleId, moduleAddr, 320 ether);
router.setMintCap(moduleId, 960 ether); // raise later

// Per-module inflow rate limit (flood protection)
router.setModuleInflowLimit(moduleId, 1 days, 100 ether); // max 100 ETH/day

// Global beacon sanity
router.setMaxDeltaBps(500); // 5% max gain per report

// Withdrawal queue bunker params
queue.setBunkerMaxRequestsPerFinalize(8);
queue.setBunkerMinRequestAge(2 days);

// Oracle slash guard
oracleAdapter.setMaxSlashBps(250); // 2.5%
```

---

## 7. Recommendations

### Immediate (This Week)
1. ✅ **Commit the fee model reconciliation** (already in working tree).
2. **Write deploy script for DVTModule** — even if minimal, it should exist for completeness.
3. **Add test for LidoPriceOracle** — currently untested.
4. **Add test for DVTModule** — even a minimal inheritance test.
5. **Update README.md** — add section documenting the lido-parity/modular phase and the two-world architecture.

### Short-Term (Next 2 Weeks)
6. **Create `011_dvtModule.ts` deploy script**.
7. **Add QuorumOracleAdapter deploy option** — make it easy to switch from single-submitter to quorum.
8. **Add inflow limiter adversarial tests**.
9. **Add `totalPooledEther` global sanity cap** to StakingRouter (e.g., `maxTotalPooledEther` that GOV can raise).
10. **Document the exact slashing response playbook** in `OPERATIONAL_RUNBOOK.md`.

### Medium-Term (Next Month)
11. **Build DVTModule Phase 2 features** (cluster coordinator hooks).
12. **Multi-validator deposit sweep** in keeper.
13. **Keeper monitoring/alerting integration**.
14. **Migrate old v2/core users** to lido-parity tokens (Rollover-style bridge).

---

## 8. Files Modified Today

```
contracts/v2/lido-parity/StakingCore.sol       (confirmed pure dilution)
contracts/v2/lido-parity/StakingRouter.sol     (removed pool inflation)
test/v2/lido-parity/e2e.spec.ts                (expectation 10.55 → 10.5)
test/v2/lido-parity/stakingCore.spec.ts        (expectation 10.55 → 10.5)
test/v2/lido-parity/stakingRouter.spec.ts      (expectation 32.55 → 32.5)
test/v2/lido-parity/e2e-router.spec.ts         (expectation gt 32.5 → equal 32.5)
```

**All 256 tests passing. No compilation errors. No warnings in lido-parity contracts.**
