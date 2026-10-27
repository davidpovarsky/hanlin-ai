# Source-First Decision Ledger — Literal Original Chat Restoration & Complete Swift AI SDK Cutover

> **2026-10-27 Update (Supersedes 2026-10-26 `KEEP_APPROVED_COMPOSER` Exception):**
> Per the 2026-10-27 P0 directive (`HANLIN - LITERAL ORIGINAL CHAT RESTORATION + COMPLETE SWIFT AI SDK AGENT CUTOVER`), the previous `KEEP_APPROVED_COMPOSER` exception for `ChatViewBottom.swift` has been **revoked and replaced** by a literal two-step restoration of all five original files (`ChatView.swift`, `ChatViewComponents.swift`, `ChatViewBottom.swift`, `ChatandFile.swift`, `ListView.swift`) from baseline commit `478cdd2c23ae2b1a52044cff52ce720830128ea2` (Step 1 checkpoint commit `83ad2725d5d5eb600dc6613f4264461613eeb10e`).
> See the authoritative 2026-10-27 documents in `docs/hanlin-original-ui-restoration/`:
> - `docs/hanlin-original-ui-restoration/BASELINE_BLOBS_AND_SYMBOLS.md`
> - `docs/hanlin-original-ui-restoration/ORIGINAL_SOURCE_DIFF_LEDGER.md`
> - `docs/hanlin-original-ui-restoration/CLASSIC_COMPONENT_RESULT_MAP.md`
> - `docs/hanlin-original-ui-restoration/SDK_TOOL_LOOP_PARITY.md`
> - `docs/hanlin-original-ui-restoration/HANLIN_ORIGINAL_DESIGN_SYSTEM.md`
> - `docs/hanlin-original-ui-restoration/PRODUCTION_LOG_DEFECT_REGISTER.md`

---

## Summary of 2026-10-27 Decisions

1. **Literal Restoration of All Five Original Files (`G1`, `G2`, `G3`)**:
   - `AI_HLY/ChatView.swift` (`2040a1a97de5cdcc427a885c6b02bb585deba3dc`)
   - `AI_HLY/Views/Components/ChatViewComponents.swift` (`7b6da5a889ca4c05288c4cb70468f2c271fc3fc0`)
   - `AI_HLY/Views/Components/ChatViewBottom.swift` (`857d342b2389226681c7432a999a8a8e31ba4c60`)
   - `AI_HLY/Views/Components/ChatandFile.swift` (`2bb464042e235ab1b58821ba7c2c134851db7e83`)
   - `AI_HLY/ListView.swift` (`ddbb0b89214fb81d7e23ef3dfbbdb63c65d623ac`)
2. **Original Blue `ChatViewBottom.swift` Visual Shell Restored (`G3`)**:
   - The original 2,379-line blue `GlassView` composer (`CustomCorners(tl: 20, tr: 20, bl: 30, br: 30)`, `.hlBlue.opacity(0.25)` shadow, `ActionButtonsView`, `modelSelector`, `sourceSelector`, floating Canvas & scroll-to-bottom buttons) is restored, with `NativeMultilineTextEditor` embedded inside `inputFieldSection`.
3. **All 9 Competing Modern Chat UI Files Deleted (`G2`)**:
   - `AgentActivitySummaryView.swift`, `AgentEvidenceSummaryView.swift`, `AgentInlineProcessItemView.swift`, `AgentInlineProcessView.swift`, `AgentRunTranscriptView.swift`, `AgentTranscriptActivityRow.swift`, `ChatAssistantActionsView.swift`, `ChatExecutionTimelineItemView.swift`, and `ChatUserMessageSurface.swift` were removed via `git rm`.
4. **Complete Swift AI SDK Cutover (`G4`, `G5`)**:
   - `APIManager.processSDKAgentEngine` (`SwiftAISDK.streamText`) is the sole remote tool loop; fallback to `processRemoteStream(..., useTools: true)` is eliminated; `APIManager.convertFormattedMessagesToSDKMessages` preserves typed multimodal image/file parts.
