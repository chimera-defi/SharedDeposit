# Audit Pass 1 — Modular Staking + Governance (2026-05-20)

## Result

- **Actionable finding (LOW):** `ReferralRegistry.setFeeToken` accepts any address (including zero/non-share token). If misconfigured, `claimFees()` can revert for all referrers because claims hard-call `transferShares`.
- **Accepted by design:** Module code-hash allowlist enforcement is intentionally opt-in and activated operationally after hashes are allowlisted.
- **Accepted by design:** Guardian pause path is intentionally immediate (no timelock), while unpause remains GOV/timelock controlled.
- **Accepted by design:** Quorum oracle safety depends on submitter/quorum operational setup; constructor does not pre-seed submitters.

## Evidence

- **A1 (LOW): fee token misconfiguration can brick claims**
  - `contracts/v2/modular-staking/ReferralRegistry.sol:197` (`setFeeToken(address _token)`) sets `feeToken` without non-zero/interface guard.
  - `contracts/v2/modular-staking/ReferralRegistry.sol:177` claims call `IShareTransferToken(feeToken).transferShares(...)`.

- **D1: allowlist enforcement is explicit opt-in**
  - `contracts/v2/modular-staking/StakingRouter.sol:651`–`655` only enforces code-hash checks when `enforceModuleCodeHashAllowlist == true`.
  - `docs/modular-staking/DEPLOYMENT_GUIDE.md:41`–`45` documents enabling enforcement after allowlisting.

- **D2: emergency pause intentionally bypasses timelock**
  - `contracts/v2/modular-staking/StakingRouter.sol:735` and `:772` (`pauseModule`, `pause`) are `onlyRole(GUARDIAN)`.
  - `docs/modular-staking/UPGRADE_PATH.md:30` states guardian can pause immediately; GOV unpauses.

- **D3: quorum oracle is ops-sensitive by construction**
  - `contracts/v2/modular-staking/QuorumOracleAdapter.sol:19`–`21` tracks `quorum` and `submitterCount` separately.
  - `contracts/v2/modular-staking/QuorumOracleAdapter.sol:74`–`83` constructor sets quorum but not submitters.
  - `contracts/v2/modular-staking/QuorumOracleAdapter.sol:203`–`208` submitters are added post-deploy.

## Next steps

1. Harden `ReferralRegistry.setFeeToken` with `address(0)` rejection and a lightweight interface sanity check (or restrict to known `StToken` contract).
2. Add a deployment assertion that `StakingRouter.enforceModuleCodeHashAllowlist == true` before opening deposits.
3. Add a deployment assertion that quorum oracle has `submitterCount >= quorum` and at least 2 independent submitters.
