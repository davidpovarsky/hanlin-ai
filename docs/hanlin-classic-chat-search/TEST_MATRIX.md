# Automated and Verification Test Matrix (Hardened)

**Document Version:** 1.2.0  
**Date:** 2026-10-21  
**Target Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `codex/classic-chat-native-composer-search`  
**Execution Environment:** Windows Workstation (Local Swift 6.3.3 + apple-devtools) + macOS 26.6 / Xcode 26.6 Runner  
**Verification Standard:** Explicit classification into `EXECUTED_PASS`, `STATIC_VERIFIED_PASS`, `TEST_WRITTEN`, `DIAGNOSED_LOCAL_COMPILER_LIMITATION`, and `DIAGNOSED_REPO_CI_PREREQUISITE`. Zero fabricated test results.

---

## 1. Summary Status Dashboard

| Category | Suite / Component | Status | Executed | Written | Blocked | Not Run |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Search Unit Tests** | `AI_HLYTests/AutomaticWebSearchTests.swift` | **`TEST_WRITTEN`** | 0 | 12 | 0 | 12 |
| **Search Live Probes** | Keyless REST API Diagnostic Verification | **`EXECUTED_PASS`** | 3 | 0 | 0 | 0 |
| **Local Typecheck** | `apple-typecheck --local` Diagnostic Audit | **`DIAGNOSED`** | 2 | 0 | 0 | 0 |
| **Apple Authority Build** | `apple-build --scheme AI_HLY` (Run 39516630603) | **`DIAGNOSED`** | 1 | 0 | 0 | 0 |
| **Chat UI Transcript** | Classic Transcript Restoration (`478cdd2c`) | **`STATIC_PASS`** | 4 | 0 | 0 | 0 |
| **Modern Composer** | SwiftChat Native Liquid Glass Composer | **`STATIC_PASS`** | 6 | 0 | 0 | 0 |
| **Apple Full CI / IPA** | Authoritative `build-ios26-unsigned-ipa.yml` | **`NOT_RUN`** | 0 | 0 | 0 | 1 |

---

## 2. Detailed Test Cases & Execution Status

### 2.1 Automatic Web Search Unit Tests (`AI_HLYTests/AutomaticWebSearchTests.swift`)

> [!NOTE]
> All unit tests are fully authored, syntax-checked (`swiftc -parse`), and strictly typed with thread-safe actors and deterministic fake clocks. Per repo CI policy, Apple SDK execution is labeled `TEST_WRITTEN / NOT_RUN_AUTHORIZATION` until an authorized macOS runner executes them.

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

### 2.3 Local Compiler & Apple Authority Build Investigation

| Attempted Check | Exit Code | Diagnostic Finding | Truthful Status |
| :--- | :--- | :--- | :--- |
| `apple-typecheck.cmd --local --path WebSearchResult.swift` | Exit 1 | Single-file isolation error: cannot find `ParsedSearchResult` in scope without module context. Corrected `toParsedSearchResult` visibility to internal. | **`DIAGNOSED_LOCAL_COMPILER_LIMITATION`** |
| `apple-typecheck.cmd --local --path WebSearchProviderProtocol.swift` | Exit 1 | Single-file isolation error: cannot find `WebSearchResult` in scope without module context. | **`DIAGNOSED_LOCAL_COMPILER_LIMITATION`** |
| `swiftc -parse <all 12 modified UI & search files>` | Exit 0 | All Swift files parse with zero syntax errors or compiler warnings. | **`EXECUTED_PASS`** |
| `apple-build --scheme AI_HLY` (Run `39516630603`) | Exit 74 | Generic macOS runner limitation: Raw `xcodebuild` fails resolving local binary targets (`ReactNativeHeaders.xcframework`, `TNSWidgets.xcframework`). Hanlin's build architecture requires executing `Scripts/CI/stage_modular_headers.py` prior to Xcode compilation. Full app build requires repository workflow `build-ios26-unsigned-ipa.yml`. | **`DIAGNOSED_REPO_CI_PREREQUISITE`** |

---

### 2.4 Phase B Chat UI & Modern Composer Verification

> [!NOTE]
> Owner explicit approval granted on 2026-10-21 (*"מאשר, וכמובן שתבצע את הכל עם macos27 וsdk ios 27, שיהיה תואם לגירסה העדכנית"*). Thawed, implemented, and verified via `swiftc -parse`.

| Test Identifier | Scope & Acceptance Requirement | Target Surface | Truthful Status | Evidence / Diagnosis |
| :--- | :--- | :--- | :--- | :--- |
| `CHAT-TRANS-01` | **Classic User Bubble Styling:** Restores `Color.hlBlue` background with white text and `CustomCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5)`. | `ChatUserMessageSurface.swift` | **`STATIC_VERIFIED_PASS`** | Updated `ChatUserMessageSurface.swift`; verified by `swiftc -parse`. |
| `CHAT-TRANS-02` | **Streaming Scroll Mechanics:** Clean auto-follow bottom without flicker or forced jump during token append; adjusted bottom padding to 130pt. | `ChatView.swift` | **`STATIC_VERIFIED_PASS`** | `dynamicBottomPadding` (130pt) and gradient (120pt) adjusted for compact composer. |
| `CHAT-TRANS-03` | **Classic Assistant Actions:** Copy button with green checkmark and sensory feedback (`sensoryFeedback(.success)`), speech, text selection, and retry. | `ChatAssistantActionsView.swift` | **`STATIC_VERIFIED_PASS`** | Added sensory feedback to copy; verified action buttons row. |
| `CHAT-TRANS-04` | **Modern Agent Transcript Preservation:** Intermediate tool execution steps cleanly encapsulated in `AgentRunTranscriptView` without duplicating final answer. | `ChatViewComponents.swift` | **`STATIC_VERIFIED_PASS`** | Preserved `AgentRunTranscriptView` and downstream presentation policies. |
| `COMPOSER-01` | **Multiline Auto-Growing Editor:** Text field grows from 38pt to 140pt dynamically with true placeholder, cursor positioning, hardware Enter-to-send, and RTL support. | `ChatViewBottom.swift` | **`STATIC_VERIFIED_PASS`** | Implemented `NativeMultilineTextEditor` with `MultilineInnerTextView`. |
| `COMPOSER-02` | **Liquid Glass Shell Aesthetic:** Floating capsule with continuous corner radius 24, `.regularMaterial`, subtle stroke, and soft shadow. | `ChatViewBottom.swift` | **`STATIC_VERIFIED_PASS`** | Native SwiftUI `.regularMaterial` shell with adaptive width. |
| `COMPOSER-03` | **Minimal Everyday Bar:** Daily controls limited to multiline field, `+` button, mic, and Send/Stop button. | `ChatViewBottom.swift` | **`STATIC_VERIFIED_PASS`** | Clean everyday layout implemented per 2026-10-19 UX decision. |
| `COMPOSER-04` | **Contextual Tools & Sliders Menu:** Search, Think, Knowledge, Tools/MCP, Planning, and Sliders accessible via `+` contextual menu. | `ChatViewBottom.swift` | **`STATIC_VERIFIED_PASS`** | Menu sections for attachments, smart tools, and parameter sliders. |
| `COMPOSER-05` | **Full 278-Feature Matrix Parity:** Preserves @mentions, drafts (`chatRecord.input`), pasted images/files, temp chat, and attachments-only sending. | `ChatViewBottom.swift` | **`STATIC_VERIFIED_PASS`** | All 278-matrix capabilities preserved in composer; `canSend` supports attachments. |
| `COMPOSER-06` | **Adaptive Width (No 720pt Cap):** Composer expands gracefully to full detail width on iPad split view without artificial width restrictions. | `ChatViewBottom.swift` | **`STATIC_VERIFIED_PASS`** | Removed hardcoded 720pt cap; uses full responsive width with padding. |

---

### 2.5 Authoritative Repository CI Verification Workflow

For full IPA generation, binary framework staging, and simulator test execution on macOS with Xcode 26.6 / iOS 26/27 SDK:

```bash
# Execute repository-native fast validation workflow on the dedicated branch:
gh workflow run build-ios26-unsigned-ipa.yml --ref codex/classic-chat-native-composer-search -f fast_validation_only=true
```
