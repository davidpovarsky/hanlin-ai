# Original upstream consumer repair — 19 November 2026

The actual candidate run44455722821 on c80f620ba8ed28243922728e00acffcdd439cc12 passed its native153-case contract (152passed,1skipped), but consumer44458610092 stopped at an authenticated branch-protection REST403. This source change preserves that failed result and the original app15368 server-required checks.

## Changes reviewed and applied

- After a structured authenticated REST403 only, read the exact existing private repository/base/ref/base-SHA/classic rule through the authenticated GraphQL API. Reject partial errors, wildcard or foreign rules, unknown booleans, ambiguous app bindings, and incomplete required-context/binding sets. Existing effective-rules REST validation remains required and unknown remains blocked. Administrator enforcement is now explicit.
- Preserve the primary redacted subprocess failure instead of masking missing report output as ENOENT.
- Accept GitHub's observed canonical check page URL only when repository, check ID, HTML URL and API URL match. Original app/head/external producer/consumer/run-attempt/job bindings remain mandatory; failed and superseded history remains attributable.
- Future producer dispatch uses the authoritative synchronization commit receipt, then requires both PR API and Git ref to converge to that exact commit/base within twelve attempts and fifteen seconds. Another commit/source/base is an error. The candidate and trusted consumer still bind actual execution GITHUB_SHA, so this is not an atomic-branch-dispatch claim.
- Register both new original test modules in the existing dependency-update preflight. Do not change frozen v3/c80, main proof workflow, credentials, server protections or automerge.

## Verification and remaining acceptance

Root independently reviewed all three patches and confirmed every before/after file SHA256. Node24.22.1 ran129cases,129passed. Seven original Python proof-reader cases passed. Seven changed runtime modules passed syntax checks and git diff --check passed. The first local invocation lacked semver; its raw failure is preserved. Re-running with the already installed npm-bundled semver7.8.5 via a process-local NODE_PATH passed, without package-lock/install changes. These are portable policy tests, not fresh native execution of candidate7.8.6.

The original139-file Host execution closure matches frozen d6e2e3f062633fe7a55c0f44b922c5b3321aaf4a byte/hash/blob-for-blob and no changed path intersects it. The actual immutable main workflow cbfae6eeeaa53969fa95fed18a5ba0a5548fd2ad uses the existing HANLIN_UPSTREAM_TRUSTED_SHA variable and validates checkout equality. Following publication the full remote SHA and closure will be rechecked before activating that variable.

Actual CI-token access, a successful independent proof, the deliberate same-head failure/server refusal/later green/protected merge/revert sequence, and automatic bot-origin handoff are still pending. A manual proof_run retry is already authorized but cannot prove automatic triggering. No task or phase is closed by this source-only repair.
