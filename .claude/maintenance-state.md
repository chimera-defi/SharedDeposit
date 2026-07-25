# Maintenance State

last_run: 2026-07-25
focus: observability
status: completed
completed:
  - fix(DeployHelper): import advanceTimeAndBlock from deploy_utils and await it in mine() — identifier was never imported and the call was unawaited, so mine() rejected with ReferenceError and never advanced time
  - fix(DeployHelper): qualify transferOwnershipToMultisig with `this.` in transferOwnershipToMultisigMultiple() — bare call had no binding in scope and threw ReferenceError
in_progress:
pending: [hardhat contract tests for v2/core — require Typechain generation and full Hardhat+Ethereum environment]
known_failures:

- TypeScript: Cannot find module '../types' in deploy/\*.ts — Typechain output not generated; run npx hardhat typechain first
- hardhat.config.ts(199,43) pre-existing type error
- No test runner available without full Ethereum node environment
- DeployHelper.js declares getContract() twice (lines 65 and 79); the second wins — dead code, left for the Friday dead-code pass
  skip_next_run: [skip test coverage work until hardhat typechain can run]
