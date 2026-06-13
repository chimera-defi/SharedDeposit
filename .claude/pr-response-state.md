# PR Response State
last_run: 2026-06-13T15:16

prs:
  - number: 49
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-11-02T03:46:44Z"
    attempt_count: 0
    status: skipped
    notes: Draft PR — research smart contract improvements (Cursor agent). Skip per isDraft=true rule.

  - number: 52
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-11-09T18:17:24Z"
    attempt_count: 0
    status: skipped
    notes: Draft PR — audit withdrawal queue contract (Cursor agent). Skip per isDraft=true rule.

  - number: 53
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-11-18T18:20:13Z"
    attempt_count: 0
    status: skipped
    notes: >
      Add ci tests and fuzzing v1 (Cursor agent). All CI green
      (build (20.x): success, test (20.x): success, security: success).
      No CHANGES_REQUESTED. Awaiting human review/merge.

  - number: 54
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-11-18T18:20:13Z"
    attempt_count: 0
    status: needs_human
    notes: >
      Add ci tests and fuzzing v2 (Cursor agent). CI FAILURE: slither static
      analysis fails (conclusion: failure). unit_tests and lint_and_build pass.
      Slither findings require human security review before merge.
      No CHANGES_REQUESTED (from human reviewer). Needs human to triage
      slither findings.

  - number: 61
    repo: chimera-defi/SharedDeposit
    last_activity: "2026-06-10T00:08:25Z"
    attempt_count: 0
    status: skipped
    notes: >
      chore(maintenance): 2026-06-10 - security pass. tx.origin usage filed
      as Issue #60 for human review. CI green (build (20.x): success).
      No CHANGES_REQUESTED. Awaiting human review/merge.
