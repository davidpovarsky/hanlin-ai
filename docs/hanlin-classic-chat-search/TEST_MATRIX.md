# Automated and Verification Test Matrix (Hardened)

**Document Version:** 1.5.0  
**Date:** 2026-10-21  
**Target Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `codex/classic-chat-native-composer-search`  
**Execution Environment:** Windows Workstation (Local Swift 6.3.3 + apple-devtools) + macOS 27 / Xcode 27.1 Release Candidate (`/Applications/Xcode_27.1_Release_Candidate.app`) / iOS 27.1 SDK GitHub Actions Runner  
**Authoritative CI Reference:** GitHub Actions Run [39644922799](https://github.com/davidpovarsky/hanlin-ai/actions/runs/39644922799) (Commit `010f2c51`)  
**Verification Standard:** Strict evidence reconciliation based on xcresult/JSON logs, zero fabricated test results, and explicit status vocabulary: `EXECUTED_PASS`, `REUSED_VERIFIED_PASS`, `COMPILED_CODE_VERIFIED`, `DEVICE_VERIFICATION_PENDING`.

---

## 1. Summary Status Dashboard

| Category | Suite / Component | Status | Executed | Reused Pass | Written / Pending | Not Run |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Search Unit Tests** | `AI_HLYTests/AutomaticWebSearchTests.swift` | **`EXECUTED_PASS`** | 13 | 0 | 0 | 0 |
| **Search Live Probes** | Keyless REST API Diagnostic Verification | **`EXECUTED_PASS`** | 3 | 0 | 0 | 0 |
| **CI Cache & Optimization** | `Scripts/CI/Tests/test_cache_and_ci_optimization.py` | **`EXECUTED_PASS`** | 32 | 0 | 0 | 0 |
| **Local Typecheck & Parse** | Local Swift 6.3.3 (`swiftc -parse`) Audit | **`EXECUTED_PASS`** | 13 | 0 | 0 | 0 |
| **Apple Authority Build** | Full arm64 iPad Simulator Build (`xcodebuild`) | **`EXECUTED_PASS`** | 1 | 0 | 0 | 0 |
| **Chat UI Transcript** | Classic Transcript Restoration (`478cdd2c`) | **`COMPILED_CODE_VERIFIED`** | 0 | 0 | 4 | 0 |
| **Modern Composer** | SwiftChat Native Liquid Glass Composer | **`COMPILED_CODE_VERIFIED`** | 0 | 0 | 7 | 0 |
| **Provider Conformance** | 77 Provider Contract Tests (`generate_provider_conformance_summary.py`) | **`NOT_RUN`** | 0 | 0 | 0 | 77 |
| **Simulator App Launch** | Fast App Launch Smoke (`simctl launch` + 15s PID monitor) | **`EXECUTED_PASS`** | 1 | 0 | 0 | 0 |

---

## 2. Authoritative CI Execution Evidence (Run 39644922799)

The full fast validation workflow was executed on GitHub Actions under commit `010f2c51`:

1. **Host Environment:** macOS 27.0.1 (Build 26A434) on Apple Silicon runner.
2. **Toolchain:** Xcode 27.1 Release Candidate (`/Applications/Xcode_27.1_Release_Candidate.app`, Build 27A9275).
3. **Target Simulator:** `iPad mini (A17 Pro)`, OS 27.0 (Build 24A434), UDID `829350AC-177C-4B4B-AC93-3673F6DD8302`.
4. **App Compilation:** Full arm64 iPad Simulator App compiled cleanly into `.app` bundle.
5. **Unit Test Execution:** All 13 unit tests executed and passed without any failure (`08-downstream-unit-test-results.json`).
6. **Simulator Fast Launch Smoke:**
   - Command: `xcrun simctl launch 829350AC-177C-4B4B-AC93-3673F6DD8302 com.itorah.chavrusachat`
   - Spawned PID: **57148** (`launch-pid.txt`)
   - Liveness Monitoring: **15 seconds** continuous alive check completed without crash (`alive-duration-seconds.txt`).

---

## 3. Automatic Web Search Unit Tests (`AI_HLYTests/AutomaticWebSearchTests.swift`)

| Test Identifier | Method Name | Description & Acceptance Requirement | Measured Duration (Run 39644922799) | Final Status |
| :--- | :--- | :--- | :--- | :--- |
| `SEARCH-DEC-01` | `youAdapterDecodesFixture` | **You.com Decoding:** Decodes real JSON fixture with string/array snippets, URL, and thumbnail. | 0.039s | **`EXECUTED_PASS`** |
| `SEARCH-DEC-02` | `tavilyAdapterDecodesFixture` | **Tavily Decoding:** Decodes real Hebrew results fixture with scores, titles, and content. | 0.0051s | **`EXECUTED_PASS`** |
| `SEARCH-DEC-03` | `keenableAdapterDecodesFixture` | **Keenable Decoding:** Decodes public endpoint fixture with acquisition date and description. | 0.0054s | **`EXECUTED_PASS`** |
| `SEARCH-CB-01` | `circuitBreakerStrictlyEnforcesCooldown` | **Strict Cooldown:** Rate-limited provider is strictly skipped on cooldown without server hits. | 0.038s | **`EXECUTED_PASS`** |
| `SEARCH-CB-02` | `allProvidersOnCooldownThrows` | **Cooldown Circuit Breaker:** When all providers are in cooldown, deterministically throws without looping. | 0.045s | **`EXECUTED_PASS`** |
| `SEARCH-REL-01` | `jerusalemPrayerTimesRejectsHotelSpam` | **Adversarial (Torah vs Hotels):** Rejects hotel booking spam masquerading as Jerusalem prayer times. | 0.0028s | **`EXECUTED_PASS`** |
| `SEARCH-REL-02` | `swiftUIQueryRejectsCardGameSpam` | **Adversarial (Tech vs Games):** Rejects card game "Bridge" results for technical SwiftUI query. | 0.0005s | **`EXECUTED_PASS`** |
| `SEARCH-CACHE-01`| `canonicalCacheNormalizesWhitespace` | **Canonical Cache:** Irregular internal whitespace (`"SwiftUI   iOS   27"`) resolves to same cache. | 0.00068s | **`EXECUTED_PASS`** |
| `SEARCH-DIAG-01` | `diagnosticBypassesCache` | **Diagnostic Probe Bypass:** Diagnostic test bypasses cache to force live probe. | 0.00096s | **`EXECUTED_PASS`** |
| `SEARCH-MIG-01` | `explicitlyDisabledManualProviderPreserved`| **Migration Invariant:** Manual provider configured by user but turned OFF is NOT forced to auto. | 0.036s | **`EXECUTED_PASS`** |
| `SEARCH-MIG-02` | `deduplicationRemovesRedundantAutomaticRows`| **Deduplication Pruning:** Prunes redundant automatic rows if duplicates exist in database. | 0.019s | **`EXECUTED_PASS`** |
| `SEARCH-DEAD-01`| `hardDeadlineCancelsSlowProviderPromptly` | **Hard Deadline Concurrency:** Task group races operation against 150ms deadline; slow provider is cancelled promptly and does NOT pollute cache. | 0.21s | **`EXECUTED_PASS`** |
| `SEARCH-REL-03` | `hebrewNiqqudAndGershayimRelevance` | **Hebrew Diacritics Preservation:** Query with niqqud and gershayim (`רַשִׁ"י פָּרָשַׁת נֹחַ`) matches plain Hebrew content. | 0.0092s | **`EXECUTED_PASS`** |

---

## 4. Live Diagnostic Probes (Executed on Windows Workstation)

| Provider | Query | Status Code | Latency | Result Count & Evidence | Truthful Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **You.com Keyless** | `"SwiftUI"`, `"זמני תפילה ירושלים"` | HTTP 200 | ~220ms | 2 structured results, valid Hebrew Torah/Zmanim sites returned. | **`EXECUTED_PASS`** |
| **Tavily Keyless** | `"SwiftUI"`, `"זמני תפילה ירושלים"` | HTTP 200 | ~2.5s | 2 structured results with relevance scores, valid Hebrew content. | **`EXECUTED_PASS`** |
| **Keenable Public** | `"SwiftUI"`, `"זמני תפילה ירושלים"` | HTTP 200 | ~1.8s | 2 structured results from documentation index. | **`EXECUTED_PASS`** |

---

## 5. Chat UI Transcript & SwiftChat Composer Matrix

| Test Identifier | Scope & Acceptance Requirement | Target Surface | Status | Evidence / Notes |
| :--- | :--- | :--- | :--- | :--- |
| `CHAT-TRANS-01` | **Classic User Bubble Styling:** Restores `Color.hlBlue` background with white text and `CustomCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5)`. | `ChatUserMessageSurface.swift` | **`COMPILED_CODE_VERIFIED`** | Implemented with resolvedMaxWidth cap; verified by syntax parse and Xcode 27 compilation. |
| `CHAT-TRANS-02` | **Streaming Scroll Mechanics:** Clean auto-follow bottom without flicker or forced jump during token append; adjusted bottom padding to 130pt. | `ChatView.swift` | **`COMPILED_CODE_VERIFIED`** | `dynamicBottomPadding` (130pt) and gradient (120pt) tuned for compact composer. |
| `CHAT-TRANS-03` | **Classic Assistant Actions:** Copy button with green checkmark and sensory feedback (`sensoryFeedback(.success)`), speech, text selection, and retry. | `ChatAssistantActionsView.swift` | **`COMPILED_CODE_VERIFIED`** | Added sensory feedback to copy; action buttons row verified in source. |
| `CHAT-TRANS-04` | **Modern Agent Transcript Preservation:** Intermediate tool execution steps cleanly encapsulated in `AgentRunTranscriptView` without duplicating final answer. | `ChatViewComponents.swift` | **`COMPILED_CODE_VERIFIED`** | Downstream bridge policies preserved intact. |
| `COMPOSER-01` | **Multiline Auto-Growing Editor:** Text field grows from 38pt to 140pt dynamically with true placeholder, cursor positioning, and RTL support. | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | `NativeMultilineTextEditor` with `MultilineInnerTextView`. Accessibility ID `hanlin-chat-input` configured. |
| `COMPOSER-02` | **Liquid Glass Shell Aesthetic:** Floating capsule with continuous corner radius 24, `.glassEffect(.regular.interactive(), in: ...)` on iOS 26+, falling back to `.regularMaterial`. | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | Uses native `.glassEffect` with version fallback. |
| `COMPOSER-03` | **Minimal Everyday Bar:** Daily controls limited to multiline field, `+` button, mic, and Send/Stop button (`hanlin-chat-send`). | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | Clean everyday layout implemented per 2026-10-19 UX decision. |
| `COMPOSER-04` | **Contextual Tools & Sliders Menu:** Search, Think, Knowledge, Tools/MCP, Planning, and Sliders accessible via `+` contextual menu. | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | Contextual menus wired to active capability flags. |
| `COMPOSER-05` | **Full 278-Feature Matrix Parity:** Preserves @mentions, drafts (`chatRecord.input`), pasted images/files, temp chat, and attachments-only sending (`canSend`). | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | All input triggers and attachments preserved. |
| `COMPOSER-06` | **Adaptive Width (No 720pt Cap):** Composer expands gracefully to full detail width on iPad split view without artificial width restrictions. | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | Removed hardcoded 720pt cap; responsive horizontal padding. |
| `COMPOSER-07` | **Hardware Return & Shift+Return:** Native `UIKeyCommand` for Return (send) and Shift+Return (newline), with `markedTextRange == nil` guard to prevent IME premature send. | `ChatViewBottom.swift` | **`COMPILED_CODE_VERIFIED`** | Replaced fragile `isiOSAppOnMac` check with native UIKit key commands. Hardware test: `DEVICE_VERIFICATION_PENDING`. |

---

## 6. Execution Command for Remote Apple Authority Verification

```bash
gh workflow run build-ios26-unsigned-ipa.yml \
  --ref codex/classic-chat-native-composer-search \
  -f fast_validation_only=true \
  -f compare_base_sha=aba9f317 \
  -f exact_test_selector=AI_HLYTests/AutomaticWebSearchTests
```
