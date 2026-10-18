# Hanlin AI — Team Assignments & Work Routing

**Asana Project:** [Hanlin AI (1219603102275846)](https://app.asana.com/0/1219603102275846/list)  
**Base Branch:** `codex/agent-skills-embedded-results`  
**Setup PR:** https://github.com/davidpovarsky/hanlin-ai/pull/2  
**Setup Task:** `1219611656715428`

---

## 1. Project Scope & Technical Boundaries
- **FROZEN CHAT UI (WX-14):** `AI_HLY/ChatView.swift`, `ChatViewBottom.swift`, `ChatViewComponents.swift`, and `ChatandFile.swift` are strictly FROZEN. Do not touch or modify without explicit owner approval.
- Widgets, MiniApps, Skill execution isolation, NativeScript runtime, and TorahLibraryKit integration.
- Future Classic Chat UI work remains in FUTURE BACKLOG until the current 23 tasks are completed and authorized.

---

## 2. Active Open Tasks & Role Assignments

| Task / Area | Logical Lead | Reviewer / QA | Scope & Constraints |
|---|---|---|---|
| **[P0][WX-11..13] TorahEvidenceStore Scoping** | דנה (dana) | נועם (noam) + רוני (roni) | Scope `TorahEvidenceStore` by session/chat identity, enforce TTL and cleanup; prevent cross-session access. |
| **[P0][WX-11] OCR attachment_handle Resolver** | דנה (dana) | נועם (noam) + רוני (roni) | Require authorized session resolver for attachments instead of raw filesystem traversal. |
| **[P0][WX-12] Torah Internal Navigation & Links** | נועם (noam) | תומר (tomer) + רוני (roni) | Fix `chavrusachat://` navigation and deep links to Maktabah. Resolve scheme mismatch. |
| **[P0][Intents] NativeScript Resume Permissions** | דנה (dana) | נועם (noam) + רוני (roni) | Enforce capability checks and prevent replay/stale generation during `processPendingResumeCommands`. |
| **[P0][SEC-01..02] Separate read/execute skill tools** | דנה (dana) | נועם (noam) | Remove `read_skill_resource` execution alias; isolate workspace directories for skill execution. |
| **[P0][WX-01..04] Expo Widget Wire Format** | נועם (noam) | רוני (roni) | Adapt JS JSON to Swift `HanlinValue` dictionary and parse ISO-8601 `validUntil`. |
| **[P0] 18 Provider Conformance Tests** | רוני (roni) | נועם (noam) | Investigate and run the 18 `NOT_RUN` tests from artifact 12047589476; record exact statuses. |
| **[P0][FINAL-03..12] Final Verification Gates** | רוני (roni) | Owner | Verify iPadOS 27 target (no 26.0 override), run Runtime Tooling collector, and audit ledger. |
| **[P1] 493 MASTER Acceptance Ledger** | רוני (roni) | Owner | Produce updated acceptance ledger on current HEAD with genuine execution provenance. |
| **[P1] WidgetKit Signing & App Groups** | דנה (dana) | תומר (tomer) | Audit `group.com.davidpovarsky.itorah` vs `group.com.itorah.*` entitlements. |

---

## 3. Mandatory Subagent Delegation & Approval Gates
- **חובת האצלה:** הסוכן הראשי פועל כמתאם בלבד ומחויב להפעיל סוכני משנה (`invoke_subagent`). כל קוד מועבר לרוני לאימות.
- **Chat UI Freeze:** Modifying the 4 frozen Chat UI files is strictly prohibited without explicit owner permission.
- **Release & Merges:** PR merges to `main`, TestFlight, or unsigned IPA distribution require owner approval.
- **Physical Device:** Tasks with physical iPad requirements remain open until verified on hardware.
- **Asana Policy:** Autonomous updates and verified completion are authorized per `docs/ai-team/ASANA_POLICY.md`.
