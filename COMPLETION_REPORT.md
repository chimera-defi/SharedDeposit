# SharedStake V2 Modular Staking Completion Report (Current State)

**Date:** 2026-05-08  
**Status:** In-progress master PR, validation baseline green for modular contracts + fork E2E

## Delivered

1. Canonical naming migration
   - Product/docs naming aligned to `SharedStake V2 Modular Staking`.
   - Oracle renamed to `StEthPriceOracle` across contract, test, and deploy surfaces.

2. Core modular coverage
   - Full modular staking suite passing (`223 passing`).
   - Fuzz/invariant suite passing (`19 passing`).

3. Security hardening + triage
   - Transfer-safety hardening in `WstToken` (`SafeERC20`).
   - Slither-driven cleanup for medium-noise items (state ordering, tuple/discard, init clarity).
   - Current modular residuals: 2 medium findings accepted by design:
     - `divide-before-multiply` (`FeeController`)
     - `locked-ether` (`StakingCore`)

4. Deploy/E2E execution path unblocked
   - Local governance fallback for modular deploy scripts (`accounts.multiSig ?? accounts.deployer`).
   - `deploy/helpers/governance.ts` made non-executable for hardhat-deploy recursion.
   - Address sync pipeline extended to include modular contract keys consumed by `/v2`.
   - Fork E2E path (`bun run test:e2e:fork`) now runs end-to-end on local Anvil and passes:
     - `tests/e2e/airdrop.spec.js`
     - `tests/e2e/stake-approve-flow.spec.js`
     - `tests/e2e/modular-staking-v2.spec.js`

5. Frontend modular flow reliability
   - `/v2` store now auto-bootstraps provider from `window.ethereum` when wallet provider state is missing.
   - Numeric form inputs are normalized before `ethers.parseEther(...)`, removing flaky INVALID_ARGUMENT errors during stake/wrap/request flows.

6. Hardening gate suites explicitly validated
   - Role/access sweep (`roleAccess.spec.ts`)
   - Oracle behavior (`stEthPriceOracle.spec.ts`, `quorumOracleAdapter.spec.ts`, `quorumOracleOperational.spec.ts`)
   - Queue stress (`withdrawalQueueV2.spec.ts`, `scenarioTests.spec.ts`)
   - Combined result: `61 passing`

## Validation Evidence

```bash
cd SharedDeposit
npm run compile
npx hardhat test $(ls test/v2/modular-staking/*.spec.ts)
npx hardhat test test/v2/modular-staking/fuzz.spec.ts

cd ..
bun run test:e2e:fork
```

Observed:
- compile: pass
- modular tests: 223 passing
- fuzz tests: 19 passing
- fork e2e: 3 passed

## Remaining for Final Master-PR Closure

1. Wallet-extension strict E2E (`test:e2e:wallet:strict`) once required env is provided.
2. Optional dependency vulnerability remediation (UI/contract package audits) in dedicated follow-up PR(s) if we keep master PR scope focused on modular staking parity.
   - Root UI audit snapshot: 36 vulnerabilities (14 high, 21 moderate, 1 low).
   - `SharedDeposit` audit snapshot: 9 vulnerabilities (3 critical, 2 high, 3 moderate, 1 low).
