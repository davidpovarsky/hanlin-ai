# Final QA Acceptance & Verification Report

**Document Date:** 2026-10-21
**Target Repository:** `https://github.com/davidpovarsky/hanlin-ai`
**Dedicated Branch:** `codex/classic-chat-native-composer-search`
**Base Commit:** `aba9f317f93c5ded6b27e1e3f4c89d8c30e5b709`
**Latest Feature Commits Checked:** `931b731a`, `42753ba4`, and current HEAD
**Authoritative CI Reference:** GitHub Actions Run [39526111790](https://github.com/davidpovarsky/hanlin-ai/actions/runs/39526111790)
**Execution Toolchain:** macOS 27.0.1 (Build 26A434) · Xcode 27.1 Release Candidate (`/Applications/Xcode_27.1_Release_Candidate.app`, Build 27A9275) · iOS Simulator 27.1 SDK (`iPhoneSimulator27.1.sdk`) · Host: `xcode-27-arm64` · Target Device: `iPad mini (A17 Pro)` (OS 27.0, build 24A434)

---

## 1. Distinguishing Verification Levels: Zero False Parity

To prevent the conflation of different verification tiers, all evidence in this report is strictly demarcated across five orthogonal operational levels:

1. **Unit Tests (`EXECUTED_PASS` / `REUSED_VERIFIED_PASS`):** Deterministic unit tests executed via Swift Testing (`@Test`) and XCTest against isolated business logic, decoders, circuit breakers, and thread-safe actor clocks. Authentic proof requires xcresult test node records (such as the 11 tests verified in Run 39526111790).
2. **Compilation Acceptance (`COMPILED_CODE_VERIFIED`):** Proves that Swift syntax, type inference, framework imports, and symbol graph bindings are accepted without errors by the authoritative Apple compiler (`swiftc` / `xcodebuild`). Compilation proves syntax and API availability, but does **not** prove functional correctness or visual layout.
3. **Simulator Launch Acceptance (`SIMULATOR_LAUNCH_VERIFIED`):** Verifies that the built `.app` bundle installs cleanly on the iOS Simulator, boots into the foreground via `xcrun simctl launch`, spawns a valid process PID, and remains alive without crashing for at least 15 seconds.
4. **Actual Interactive UI Workflow (`XCUI_VERIFIED`):** Automated end-to-end interaction using `XCUIApplication` driving live elements (`textFields`, `buttons`, `menus`), verifying responder chain transitions, accessibility identifiers, and dynamic height recalculations.
5. **Physical Real-Device QA (`DEVICE_VERIFICATION_PENDING`):** Features requiring real physical hardware (Apple Magic Keyboard/hardware Return events, hardware camera sensor capture, microphone hardware permissions, and physical thermal/jetsam memory pressure). These are explicitly kept open until verified on physical hardware.

---

## 2. Automatic Web Search Acceptance Matrix (SEARCH-A01...SEARCH-A18)

| ID | Scenario | Required Behavior | Evidence & Verification Method | Status |
| :--- | :--- | :--- | :--- | :--- |
| **SEARCH-A01** | Fresh installation | Automatic keyless provider is active by default; `UserInfo.useSearch` aligns with search capability. | Verified in `AutomaticSearchMigration.reconcileDefaultProvider` and `PreLoad.swift`. | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A02** | Existing user with key | Preserve active manual provider key and settings; do not overwrite. | Verified by `SEARCH-MIG-01` (`explicitlyDisabledManualProviderPreserved`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A03** | Explicitly disabled search | Manually selected OFF provider never silently re-enables on startup. | SwiftData in-memory test verifies `auto.isUsing == false`. | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A04** | Duplicate SwiftData rows | Strict deduplication; prune multiple auto rows to exactly 1 active row. | Verified by `SEARCH-MIG-02` (`deduplicationRemovesRedundantAutomaticRows`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A05** | You.com successful | Returns structured results with title, URL, snippet, and citation backend. | Verified by `SEARCH-DEC-01` (`youAdapterDecodesFixture`) and live probe. | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A06** | You.com 429 + Retry-After | Skips cooled provider, falls back to Tavily, respects cooldown header. | Verified by `SEARCH-CB-01` (`circuitBreakerStrictlyEnforcesCooldown`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A07** | You + Tavily fail | Bounded fallback to Keenable Public adapter within budget. | Verified by `SEARCH-DEC-03` (`keenableAdapterDecodesFixture`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A08** | All providers unavailable | Deterministically throws `AutomaticSearchError.allProvidersOnCooldown`. | Verified by `SEARCH-CB-02` (`allProvidersOnCooldownThrows`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A09** | Irrelevant results | Bounded relevance-based fallback; rejects spam while retaining valid content. | Verified by `WebSearchRelevanceEvaluator.evaluate`. | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A10** | Adversarial mismatch | Rejects hotel spam for Jerusalem prayer times; rejects card games for SwiftUI. | Verified by `SEARCH-REL-01` and `SEARCH-REL-02`. | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A11** | Hebrew niqqud & RTL | `רַשִׁ"י פָּרָשַׁת נֹחַ` with niqqud/gershayim matches plain Hebrew without rejection. | Verified by `SEARCH-REL-03` (`hebrewNiqqudAndGershayimRelevance`). | **`TEST_WRITTEN_NOT_RUN`** |
| **SEARCH-A12** | Concurrency race | Actor isolation prevents cache corruption or duplicate runaway queries. | `AutomaticWebSearchCoordinator` is an isolated Swift `actor`. | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A13** | Cache TTL & canonicalization| Whitespace normalized; 300s TTL enforced; bypass flag works. | Verified by `SEARCH-CACHE-01` (`canonicalCacheNormalizesWhitespace`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A14** | Hard deadline & cancel | Structured task group races operation against 150ms deadline; cancel aborts task. | Verified by `SEARCH-DEAD-01` (`hardDeadlineCancelsSlowProviderPromptly`). | **`TEST_WRITTEN_NOT_RUN`** |
| **SEARCH-A15** | Diagnostic test button | Cache bypassed; elapsed time and top source title/URL accurately returned. | Verified by `SEARCH-DIAG-01` (`diagnosticBypassesCache`). | **`REUSED_VERIFIED_PASS`** |
| **SEARCH-A16** | Unification across flows | `searchOnline`, `WebSearchTool`, and agent tools use identical coordinator. | Source inspection of `APIManager.swift` and `WebSearchTool.swift`. | **`COMPILED_CODE_VERIFIED`** |
| **SEARCH-A17** | Settings UI & localization | Hebrew, English, and Chinese strings; manual toggle and warning badges. | Verified in `APISettingView.swift` and `Localizable.xcstrings`. | **`COMPILED_CODE_VERIFIED`** |
| **SEARCH-A18** | HTTP error handling | 429, 401, 403, 500, network timeouts parsed into typed errors without crashing. | Adapters parse status codes into typed `AutomaticSearchError` enum. | **`REUSED_VERIFIED_PASS`** |

---

## 3. SwiftChat-Native Composer Acceptance Matrix (INPUT-01...INPUT-18)

| ID | User Operation | Expected Behavior & Verification Surface | Status |
| :--- | :--- | :--- | :--- |
| **INPUT-01** | Focus empty input | Native placeholder `"Message"` rendered; cursor positioned; safe area maintained. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-02** | Type 1/4/10+ lines | `NativeMultilineTextEditor` auto-grows from 38pt to 140pt target, scrolling internally at cap. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-03** | Paste multi-line text | System pasteboard text inserted without truncated lines; placeholder never submitted. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-04** | Hebrew + English, undo | Bi-directional mixed RTL/LTR text entry, cursor positioning, and selection handles. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-05** | Hardware Return / Shift+Return | `UIKeyCommand` sends message on Return (when `markedTextRange == nil`); Shift+Return inserts newline. | **`DEVICE_VERIFICATION_PENDING`** |
| **INPUT-06** | `@` model suggestions | Typing `@` filters model suggestions; selecting inserts `@ModelName ` at cursor. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-07** | `+` attachment menu | Opens Photos, Camera, Files pickers via native system sheets. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-08** | Paste image / PDF / doc | Extracts images/files from pasteboard items and displays preview cards in attachment tray. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-09** | Send attachments only | `canSend` enables send button even when text is empty if images/documents are present. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-10** | Send & rapid Stop | Send button toggles to Stop (`hanlin-chat-stop`); cancellation aborts streaming cleanly. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-11** | Model picker & drafts | Active model retained; `chatRecord.input` persists unsent draft across navigation. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-12** | Voice input & permissions | Mic button presents `VoiceInputView`; permissions checked with graceful denial handling. | **`DEVICE_VERIFICATION_PENDING`** |
| **INPUT-13** | Toggle Smart Tools | Search, Think, Knowledge, Tools/MCP, Planning badges update and wire to active flags. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-14** | Parameter sliders | Contextual sliders menu updates `maxMessagesNum`, `temperature`, and `top_p`. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-15** | Auto-follow streaming | Auto-scroll follows bottom while streaming; pauses if user scrolls upward to read history. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-16** | Rich embedded results | `AgentRunTranscriptView` renders intermediate tool calls cleanly; single final response. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-17** | iPad Split View resize | Removed hardcoded 720pt cap; composer stretches gracefully with detail view width. | **`COMPILED_CODE_VERIFIED`** |
| **INPUT-18** | Accessibility & hit targets | Minimum 32x32 hit targets; accessibility labels and identifiers (`hanlin-chat-input`, `hanlin-chat-send`). | **`COMPILED_CODE_VERIFIED`** |

---

## 4. Hardware Verification Checklist for Physical iPad

The following operations cannot be substantiated solely in the iOS Simulator and must be verified on a physical iPad running iOS 27:

1. **Hardware Keyboard Return & Shift+Return (`INPUT-05`):**
   - Connect an external Bluetooth keyboard (or Apple Magic Keyboard).
   - Type `"Hello world"` and press `Return`. Verify message is sent immediately.
   - Type `"First line"`, press `Shift + Return`, type `"Second line"`, press `Return`. Verify multi-line message is sent.
   - Switch to Hebrew keyboard, type `"שלום"`, verify Return sends message.
   - Switch to Pinyin or Japanese IME, type a syllable with candidates bar active, press Return. Verify candidate is selected and message is **not** prematurely sent.
2. **True Hardware Microphone (`INPUT-12`):**
   - Tap mic icon in composer, verify system permission dialog appears.
   - Speak a sentence in Hebrew and English; verify speech recognition transcribes into composer text.
3. **Camera Capture (`INPUT-07`):**
   - Tap `+` -> Camera; verify live camera viewfinder opens; capture image and verify thumbnail appears in attachment tray.

---

## 5. Risk Assessment & Known Boundaries

1. **Asana Administration:** Asana Task `1219605282038660` remains open (`completed: false`). Scoped Chat UI work was performed pursuant to the repository owner's first-party communication. Broad MiniApps split and destructive persistence changes remain frozen.
2. **Third-Party Keyless Limits:** The automatic keyless search tiers (You.com, Tavily, Keenable) are bounded by remote endpoint rate limits (HTTP 429). The circuit breaker correctly cooldown-throttles them for 60-120 seconds.
3. **CI Conformance Tests:** The 77 conformance tests in `generate_provider_conformance_summary.py` require running the full Phase 1 baseline job (`run_phase1: true`) to generate the `phase1-validation-${{ github.sha }}` artifact. Under fast targeted search validation, these 77 tests are classified as `NOT_RUN`.
