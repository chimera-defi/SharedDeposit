# X-Ray Report (Regenerated 2026-05-20)

Scope emphasis: `contracts/v2/modular-staking`, `contracts/v2/governance`.
Context retained: full `contracts/v2` inventory from `x-ray/enumeration-pass1.txt`.

See detailed pass output: `x-ray/pass1-modular-governance.md`.

## Summary

- 1 actionable low-severity hardening item
- 3 accepted-by-design operational/security tradeoffs
- No high-confidence exploitable logic bug identified in this pass

## Actionable

- `ReferralRegistry.setFeeToken` should reject unsafe values to avoid claim-path misconfiguration risk.

## Accepted by design

- Module code-hash allowlist enforcement is opt-in and deployment-driven.
- Guardian can pause immediately (no timelock), GOV must unpause.
- Quorum oracle requires explicit post-deploy submitter/quorum setup.
