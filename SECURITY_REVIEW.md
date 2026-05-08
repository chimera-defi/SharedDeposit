# SharedStake V2 Modular Staking Security Review

**Date:** 2026-05-08  
**Scope:** `contracts/v2/modular-staking/**`  
**Tooling:** Slither `0.11.5` + manual triage  

## Summary

- No critical or high-severity findings in modular staking scope.
- Two medium findings remain and are currently risk-accepted by design:
  1. `divide-before-multiply` in `FeeController.computeFees`
  2. `locked-ether` in `StakingCore`
- Previously flagged medium issues (`reentrancy-no-eth`, `uninitialized-local`, `unused-return`) were reduced via hardening changes in this branch.

## Command Evidence

### 1) Static analysis

```bash
cd SharedDeposit
npx hardhat clean
npx hardhat compile
slither . --hardhat-ignore-compile --json /tmp/slither-full-20260508-post.json
```

Observed from `/tmp/slither-full-20260508-post.json`:

- `success: true`
- total detectors emitted: `631` (entire repo, all contracts)
- modular-staking `Medium|High` findings: **2** (both medium, no high)

Filtered modular-staking medium findings:

1. `divide-before-multiply`  
   - File: `contracts/v2/modular-staking/FeeController.sol`  
   - Function: `computeFees(uint256 rewards)`  
   - Status: accepted (precision/rounding tradeoff consistent with fee model)

2. `locked-ether`  
   - File: `contracts/v2/modular-staking/StakingCore.sol`  
   - Status: accepted (contract is intended pooled-ETH accounting holder; withdrawals occur through queue flow, not arbitrary owner drain)

## Hardening Applied in This Pass

1. `WstToken` transfer hardening  
   - Switched to `SafeERC20.safeTransferFrom` / `safeTransfer`.

2. Reduced Slither medium noise in modular scope  
   - `StakingRouter.reportModuleBeaconBalance`: moved `moduleBeaconBalance[moduleId]` write before delta application.
   - `StakingCore` / `StakingRouter`: added `FeeController.getRecipients()` and removed tuple-discard pattern that triggered `unused-return`.
   - `WithdrawalQueueV2` / `StakingRouter`: explicit accumulator/struct initialization for deterministic static-analysis behavior.

## Residual Risk Notes

1. `divide-before-multiply`  
   - Current implementation intentionally rounds at fee-split boundaries.
   - If exact proportional split across both divisions is desired, migrate to `mulDiv`-based formulation and update economic tests accordingly.

2. `locked-ether`  
   - Intended architecture for staking pool accounting.
   - Operational safety depends on correct queue/oracle controls and role governance.

## Recommended Follow-up (Optional)

1. Add a dedicated "risk-acceptance" section in public docs/runbook for the two medium accepted items.
2. Add an automated CI step that filters Slither JSON to `contracts/v2/modular-staking/**` and fails only on new High/Critical findings.
