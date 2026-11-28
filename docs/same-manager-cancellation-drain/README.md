# Drain retired agent work before admitting a replacement

## Status

The eight-path source donor is c48140a7d00d0c5de1ec0933e15738acf930e7e9, based on fc5ce1bacffbf8b3cd206b83debfac406c0044ed. Two independent reviewers approved frozen R3 source. This packet records source review and exact-byte verification only: compilation, controls and native acceptance have not run for this candidate.

Two original application methods reported unresolved-write failures: startingNewRunCancelsOldRunWithoutGhostWork() and testP11OverlappingRunBSupercedesA(). Their assertions and original limits are unchanged. The retained native evidence does not identify the exact production throw frame. This change does not claim to have established the sole cause or resolved those native failures.

## Changed behavior

A replacement captures the manager request epoch and the Owner's conversation, row, generation and context authority before waiting. It revokes the superseded request's live authority synchronously and joins the captured outer producer before replacing shared request or diagnostics-recorder state. Each admission suspension is followed by authority validation; a third request, Stop or destructive mutation wins.

The existing global Coordinator supplies a reservation before that new wait. A successful reservation immediately requests cancellation of the registered global producer, while retaining its handle, active identity and recorder for the original completion paths. Already-cancelled callers make no reservation or global mutation. Reserved begin requires the exact current token and a non-cancelled task before mutation and again after the original recorder await. Original async and sync begin entries supersede older reservations while preserving their original cancellation and recorder bodies. Matching Stop cannot revoke an unrelated newer request; completion of old A cannot revoke later B or C.

Cancellation remains a request. The Session retains the actual entered dispatcher/Host task through Host return, receipt metadata and its original ordered compare-and-swap persistence. Its running state and drain include that work even if the public stream consumer has finished. The manager also joins the captured outer producer so an old catch cannot access a newly installed recorder.

A late result is admitted only as historical receipt metadata when its original invocation, tool, context, arguments, output limits and returned identity match. The result accessor repeats output admission because the original Dispatcher records its raw result before checking the maximum output size. It never converts this history into live progress, UI or split-coordinator callbacks, and never retries an effect. Missing or uncertain identity, malformed or oversized results, deleted records and failed persistence remain blocking. No cold-store write or inferred no-effect completion is introduced.

Ordinary completed producer handles do not by themselves invalidate an idle Session or its existing interaction reuse. The original Host implementation, store CAS, unresolved-write guards, workflow selectors and production deadlines are unchanged.

## Controlled regression source

The additions use the real Session, Dispatcher, attached producer tasks and Coordinator methods with explicit continuation gates. They introduce no sleep-based race oracle.

| Existing suite | Added definitions | Semantic cases | Purpose |
|---|---:|---:|---|
| AgentSessionTests | 3 | 9 | Host return and metadata CAS after cancellation; uncertain, thrown, malformed, wrong-identity and oversized results; conflicting revision and deleted row |
| HanlinAppAgentSessionOwnerTests | 3 | 4 | Captured Owner authority through retirement, competing replacement and destructive mutation |
| AgentRoundPresentationTests | 6 | 9 | Shared request order, legacy entrants, recorder suspension, matching Stop, cancelled entry and early global cancellation |

Removing the added blocks recovers each complete original test file. The six newly introduced R2 optional-reservation setup lines were adapted in R3; no original test assertion or timing allowance changed. Source totals are 12 new definitions and 22 semantic cases, pending execution.

## Review history and composition

R1's local drain mechanism was retained but its approval was held after independent review found a competing-manager request-order race. R2 added the global reservation and retained two cancellation-boundary holds. R3 closes those source-level findings with cancellation checks and immediate cancellation of the registered global producer without clearing its lifetime state. The earlier approvals, holds and final reviews are included verbatim.

The full eight-file patch and three-file R2-to-R3 delta apply and reverse exactly. The five R1 Session/Dispatcher/Owner and test files remain byte-identical through R3. The root review independently verified every original and source-donor blob and both-order composition with the separately approved Owner fixture and canonical presentation changes. Those overlaps are distinct regions of APIManager and the Owner test file; composed hashes are recorded in the review.

The source changes intersect zero of the retained 396 MiniApp SDK inputs, 99 Host inputs and 13 existing paired-native input rows. This does not exempt the changed AgentSDK and main application from their native gates. This proof directory is outside the SDK's consumed docs/agent-sdk tree.

## Required native successor

The unchanged original agent_sdk_session_only_proof request selects the complete Session, Context and Store suites in its original 60-minute job and retains the coupled original 15-minute Presentation job. The prepared expectation is 36 definitions and 42 semantic invocations, including all 33 original definitions. Actual method and argument identities must be reconciled after execution.

The original full application request separately retains the complete Owner and AgentRound suites and both historical failed methods. A package result cannot establish those application outcomes. Final composed source, original CI, integration-branch publication and fresh concurrency admission remain prerequisites; no dispatch is performed by this proof.

The lossless gzip payloads are bound to original byte sizes and SHA-256 hashes in lossless-encodings.json. Every public payload is verified from the actual committed Git object in the separate seal receipt, not merely from the working tree.
