# Hanlin AI — Team Assignments & Work Routing

**Asana Project:** [Hanlin AI (1219603102275846)](https://app.asana.com/0/1219603102275846/list)  
**Base Branch:** `codex/agent-skills-embedded-results`  
**Setup PR:** https://github.com/davidpovarsky/hanlin-ai/pull/2  
**Setup Task:** `1219611656715428`

---

## Current completion authorization — 2026-11-18

The current owner's direct authorization is recorded in ../../docs/continuation-20261117/OWNER_AUTHORIZATION_20261118.md. These old assignments are historical; one developer completes both phases without a new phase-start or frozen-file confirmation.

## 1. Project Scope & Technical Boundaries
- **Chat UI integration:** The owner has approved necessary changes to `AI_HLY/ChatView.swift`, `ChatViewBottom.swift`, `ChatViewComponents.swift`, and `ChatandFile.swift` for the current completion. Preserve the original components and verify affected behavior.
- Widgets, MiniApps, Skill execution isolation, NativeScript runtime, and TorahLibraryKit integration.
- The current Phase 2/3 Chat and split work is authorized; historical backlog sequencing does not stop it.

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

## 3. Approval Gates
- **Chat UI:** Necessary current-scope edits have explicit owner approval; visual and behavioral acceptance still require real evidence.
- **Release & Merges:** Apply the current owner authorization and actual acceptance results; do not treat historical approval requests as a new stop after authorization has been granted.
- **Physical Device:** Tasks with physical iPad requirements remain open until verified on hardware.
- **Asana Policy:** Autonomous updates and verified completion are authorized per `docs/ai-team/ASANA_POLICY.md`.
