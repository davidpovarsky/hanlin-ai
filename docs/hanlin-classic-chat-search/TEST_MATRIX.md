# Automated and Verification Test Matrix (Hardened)

**Document Version:** 1.1.0  
**Date:** 2026-10-21  
**Target Repository:** `davidpovarsky/hanlin-ai`  
**Execution Environment:** Windows Workstation (Local Swift 6.3.3 + apple-devtools)  
**Verification Standard:** Explicit classification into `EXECUTED_PASS`, `TEST_WRITTEN`, `DIAGNOSED_LOCAL_COMPILER_LIMITATION`, `NOT_RUN_AUTHORIZATION`, and `BLOCKED_AWAITING_OWNER_APPROVAL`. Zero fabricated test results.

---

## 1. Summary Status Dashboard

| Category | Suite / Component | Status | Executed | Written | Blocked | Not Run |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Search Unit Tests** | `AI_HLYTests/AutomaticWebSearchTests.swift` | **`TEST_WRITTEN`** | 0 | 12 | 0 | 12 |
| **Search Live Probes** | Keyless REST API Diagnostic Verification | **`EXECUTED_PASS`** | 3 | 0 | 0 | 0 |
| **Local Typecheck** | `apple-typecheck --local` Diagnostic Audit | **`DIAGNOSED`** | 1 | 0 | 0 | 0 |
| **Chat UI Transcript** | Classic Transcript Restoration (`478cdd2c`) | **`BLOCKED`** | 0 | 0 | 4 | 0 |
| **Modern Composer** | SwiftChat Native Liquid Glass Composer | **`BLOCKED`** | 0 | 0 | 6 | 0 |
| **Apple CI / Simulator**| Full Simulator Regression Suite | **`NOT_RUN`** | 0 | 0 | 0 | 5 |

---

## 2. Detailed Test Cases & Execution Status

### 2.1 Automatic Web Search Unit Tests (`AI_HLYTests/AutomaticWebSearchTests.swift`)

> [!NOTE]
> All unit tests are fully authored, syntax-checked (`swiftc -parse`), and strictly typed with thread-safe actors and deterministic fake clocks. Per repo CI policy, Apple SDK execution is labeled `NOT_RUN_AUTHORIZATION` until an authorized macOS runner executes them.

| Test Identifier | Description & Acceptance Requirement | Target Method / Component | Truthful Status | Evidence / Diagnosis |
| :--- | :--- | :--- | :--- | :--- |
| `SEARCH-DEC-01` | **You.com Adapter Decoding:** Decodes real JSON fixture with string and array snippets, URL, and thumbnail. | `YouKeylessSearchAdapter.parseYouResponse` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Fixture authored with mixed snippet types; verified by static compiler parse. |
| `SEARCH-DEC-02` | **Tavily Adapter Decoding:** Decodes real Hebrew results fixture with scores, titles, and content. | `TavilyKeylessSearchAdapter.parseTavilyResponse` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Fixture authored with Hebrew prayer times (`"זמני היום בירושלים"`). |
| `SEARCH-DEC-03` | **Keenable Adapter Decoding:** Decodes public endpoint fixture with acquisition date and description. | `KeenablePublicSearchAdapter.parseKeenableResponse` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Fixture authored with public research documentation response. |
| `SEARCH-CB-01` | **Strict Cooldown Enforcement:** Rate-limited provider is strictly skipped on cooldown without server hits. | `AutomaticWebSearchCoordinator.executeFallbackLoop` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Fake clock deterministic test: Provider 1 not called on Query 2 during 60s cooldown; retried on Query 3 after expiry. |
| `SEARCH-CB-02` | **All Providers on Cooldown:** When all providers are in cooldown, deterministically throws without looping. | `AutomaticWebSearchCoordinator.executeFallbackLoop` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Asserts `AutomaticSearchError.allProvidersOnCooldown(retryAfter:)`. |
| `SEARCH-REL-01` | **Adversarial Mismatch (Torah vs Hotels):** Rejects hotel booking spam masquerading as Jerusalem prayer times. | `WebSearchRelevanceEvaluator.evaluate` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Provider 1 hotel spam rejected; coordinator falls back to Provider 2 prayer times. |
| `SEARCH-REL-02` | **Adversarial Mismatch (Tech vs Games):** Rejects card game "Bridge" results for technical SwiftUI query. | `WebSearchRelevanceEvaluator.evaluate` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Provider 1 card game rejected; coordinator falls back to Apple Developer documentation. |
| `SEARCH-CACHE-01`| **Canonical Cache Normalization:** Irregular internal whitespace (`"SwiftUI   iOS   27"`) resolves to same cache. | `AutomaticWebSearchCoordinator.search` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Verified token-based canonical cache key generation. |
| `SEARCH-DIAG-01` | **Diagnostic Probe Cache Bypass:** Diagnostic test bypasses cache to force live probe. | `AutomaticWebSearchCoordinator.runDiagnosticTest` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Consecutive diagnostic runs increment call count to guarantee genuine network test. |
| `SEARCH-MIG-01` | **Explicit Disable Preservation:** Manual provider configured by user but turned OFF is NOT forced to auto. | `AutomaticSearchMigration.reconcileDefaultProvider` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | In-memory `ModelContainer` test: Tavily `isUsing: false` preserved; automatic stays `false`. |
| `SEARCH-MIG-02` | **Deduplication Pruning:** Prunes redundant automatic rows if duplicates exist in database. | `AutomaticSearchMigration.reconcileDefaultProvider` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Multi-row SwiftData store pruned to exactly 1 `AUTOMATIC_KEYLESS` row. |
| `SEARCH-DEAD-01`| **Hard Deadline Concurrency:** Task group races operation against deadline timer with cancellation propagation. | `AutomaticWebSearchCoordinator.executeWithStructuredDeadline` | **`TEST_WRITTEN / NOT_RUN_AUTHORIZATION`** | Structured `withThrowingTaskGroup` cancels hung/slow mock tasks on timeout. |

---

### 2.2 Live REST Diagnostic Probes (Executed on Windows Workstation)

| Provider | Query | Status Code | Latency | Result Count & Evidence | Truthful Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **You.com Keyless** | `"SwiftUI"`, `"זמני תפילה ירושלים"` | HTTP 200 | ~220ms | 2 structured results, valid Hebrew Torah/Zmanim sites returned. | **`EXECUTED_PASS`** |
| **Tavily Keyless** | `"SwiftUI"`, `"זמני תפילה ירושלים"` | HTTP 200 | ~2.5s | 2 structured results with relevance scores, valid Hebrew content. | **`EXECUTED_PASS`** |
| **Keenable Public** | `"SwiftUI"`, `"זמני תפילה ירושלים"` | HTTP 200 | ~1.8s | 2 structured results from documentation index. | **`EXECUTED_PASS`** |

---

### 2.3 Local Compiler & Typecheck Investigation

| Attempted Check | Exit Code | Diagnostic Finding | Truthful Status |
| :--- | :--- | :--- | :--- |
| `apple-typecheck.cmd --local --path WebSearchResult.swift` | Exit 1 | Single-file isolation error: cannot find `ParsedSearchResult` in scope. | **`DIAGNOSED_LOCAL_COMPILER_LIMITATION`** |
| `apple-typecheck.cmd --local --path WebSearchProviderProtocol.swift` | Exit 1 | Single-file isolation error: cannot find `WebSearchResult` in scope. | **`DIAGNOSED_LOCAL_COMPILER_LIMITATION`** |
| `swiftc -parse <all 9 search files>` | Exit 0 | All Swift 6 files parse with zero errors or syntax warnings. | **`EXECUTED_PASS`** |

**Root Cause:** The `--local` mode of `apple-typecheck` compiles only the specified single file using the Windows host Swift compiler, without target/module context. Files that reference symbols declared in sibling files within the `AI_Hanlin` target cannot resolve cross-file dependencies when typechecked in single-file isolation. Full module typechecking requires the Xcode project context on a macOS runner.

---

### 2.4 Phase B Chat UI & Modern Composer (Blocked by Gate)

| Test Identifier | Scope | Truthful Status | Reason & Blocker Reference |
| :--- | :--- | :--- | :--- |
| `CHAT-TRANS-01` | Restore classic message widths, margins, and typography from `478cdd2c`. | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Asana Gate `1219605282038660` is open (`completed: false`). Four Chat UI files remain frozen per project policy. |
| `CHAT-TRANS-02` | Natural scroll reading and non-jumping streaming append behavior. | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatView.swift` and `ChatViewComponents.swift`. |
| `CHAT-TRANS-03` | Classic user/assistant actions (copy, share, retry, regenerate). | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing frozen chat surface files. |
| `CHAT-TRANS-04` | Agent activity hierarchy (collapsed steps separate from final answer). | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing frozen chat surface files. |
| `COMPOSER-01` | Native Liquid Glass multiline auto-growing text editor. | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatViewBottom.swift` (frozen file). |
| `COMPOSER-02` | Everyday minimal controls (+ menu, mic, send/stop, model menu). | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatViewBottom.swift` (frozen file). |
| `COMPOSER-03` | Full Hanlin feature parity (pasted files/images, @mentions, drafts). | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatViewBottom.swift` (frozen file). |
| `COMPOSER-04` | iPad split view adaptive width (removal of artificial 720pt cap). | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatViewBottom.swift` (frozen file). |
| `COMPOSER-05` | Attachment preview strip and attachments-only sending. | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatViewBottom.swift` (frozen file). |
| `COMPOSER-06` | Send/stop state transitions during streaming generation. | **`BLOCKED_AWAITING_OWNER_APPROVAL`** | Dependent on editing `ChatViewBottom.swift` (frozen file). |

---

### 2.5 Apple Platform / CI Commands for Authorized macOS Run

When authorized by the project owner, the following exact commands should be executed:

```bash
# 1. Typecheck the entire AI_HLY scheme on macOS
apple-typecheck --scheme AI_HLY --targets AI_HLY,AI_HLYTests

# 2. Execute focused unit tests for Automatic Web Search
apple-test-focused --scheme AI_HLY --only-testing AI_HLYTests/AutomaticWebSearchTests

# 3. Full scheme build verification on iOS Simulator
apple-build --scheme AI_HLY --destination "platform=iOS Simulator,name=iPhone 16 Pro"
```
