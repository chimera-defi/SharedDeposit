# Maintenance State
last_run: 2026-06-10
focus: security
status: completed
completed: [secret scan clean; .env in .gitignore confirmed; filed Issue #60 for tx.origin in noContractAllowed modifier (medium severity, architectural)]
in_progress:
pending: [hardhat contract tests for v2/core — require Typechain generation and full Hardhat+Ethereum environment]
known_failures:
  - TypeScript: Cannot find module '../types' in deploy/*.ts — Typechain output not generated; run npx hardhat typechain first
  - hardhat.config.ts(199,43) pre-existing type error
  - No test runner available without full Ethereum node environment
skip_next_run: [skip test coverage work until hardhat typechain can run]
