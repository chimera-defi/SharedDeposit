# SharedStake V2 Modular Staking Progress

**Date:** 2026-05-08  
**Branch:** `feat/sharedstake-v2-modular-staking-master`  
**Scope:** master-PR parity + modular staking + DVT + hardening + docs

## Completed In This Validation Cycle

1. Contract/test naming normalization completed for oracle surface:
   - `LidoPriceOracle` -> `StEthPriceOracle`
   - `MockILidoStETH` -> `MockIStEth`
   - `lidoPriceOracle.spec.ts` -> `stEthPriceOracle.spec.ts`

2. Modular staking test matrix executed and passing:
   - `npx hardhat test $(ls test/v2/modular-staking/*.spec.ts)` -> **223 passing**
   - `npx hardhat test test/v2/modular-staking/fuzz.spec.ts` -> **19 passing**

3. Security hardening applied:
   - `WstToken` uses `SafeERC20` transfer wrappers.
   - `StakingRouter` beacon-report state ordering tightened.
   - `FeeController.getRecipients()` added; tuple-discard warnings removed.
   - explicit local initialization in queue/router accumulators.

4. Slither triage completed:
   - Modular scope now has **2 medium** findings (accepted by design), no high/critical.

5. Fork E2E harness brought to executable state on local Anvil:
   - Fixed deploy-path blockers:
     - Local governance signer fallback for modular deploy scripts.
     - `deploy/helpers/governance.ts` marked non-executable for hardhat-deploy recursion.
   - Updated E2E flow robustness (`stake-approve-flow`) for local determinism.
   - `bun run test:e2e:fork` now reaches completion with `3 passed`:
     - `tests/e2e/airdrop.spec.js`
     - `tests/e2e/stake-approve-flow.spec.js`
     - `tests/e2e/modular-staking-v2.spec.js`

6. Address and frontend modular wiring hardened:
   - `scripts/contracts/_lib.sh` now exports modular addresses (`stakingCore`, `stToken`, `wstToken`, `withdrawalQueueV2`, router/module/oracle keys) into synced UI address maps.
   - `src/stores/modularStaking.js` now resolves per-chain addresses from `src/contracts/addresses/*.json` and auto-bootstraps provider from `window.ethereum` when missing.
   - Amount normalization added before `ethers.parseEther(...)` to handle numeric `v-model` inputs in `/v2` flows.

7. Security/hardening gate evidence captured:
   - Role/access control sweep, oracle behavior suites, and queue TURBO/BUNKER stress scenarios executed together:
     - `npx hardhat test test/v2/modular-staking/roleAccess.spec.ts test/v2/modular-staking/stEthPriceOracle.spec.ts test/v2/modular-staking/quorumOracleAdapter.spec.ts test/v2/modular-staking/quorumOracleOperational.spec.ts test/v2/modular-staking/withdrawalQueueV2.spec.ts test/v2/modular-staking/scenarioTests.spec.ts`
     - Result: **61 passing**

## Current Known Gaps

1. Wallet-extension strict E2E remains environment-gated:
   - Missing:
     - `PW_WALLET_EXTENSION_PATH`
     - `PW_WALLET_EXTENSION_ID`
     - `PW_WALLET_TEST_ADDRESS`

2. Toolchain warning in harness:
   - Hardhat warns Node.js 24 is unsupported; recommend Node 20/22 for CI stability.

3. Dependency security backlog (separate from modular contract security):
   - Root UI (`bun audit --level moderate`): 36 vulnerabilities (14 high, 21 moderate, 1 low).
   - `SharedDeposit` (`npm audit --audit-level=high --omit=dev`): 9 vulnerabilities (3 critical, 2 high, 3 moderate, 1 low).

## Latest Command Outcomes (2026-05-08)

```bash
# contracts
cd SharedDeposit
npm run compile
npx hardhat test $(ls test/v2/modular-staking/*.spec.ts)
npx hardhat test test/v2/modular-staking/fuzz.spec.ts

# static security
slither . --hardhat-ignore-compile --json /tmp/slither-full-20260508-post.json

# app/fork e2e (requires local anvil + governance env for this shell)
cd ..
bun run test:e2e:fork
```

Observed:
- Compile: pass
- Modular suite: 223 passing
- Fuzz suite: 19 passing
- Fork E2E (`airdrop`, `stake-approve-flow`, `modular-staking-v2`): 3 passed
