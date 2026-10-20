# Baseline and Preservation Matrix (Hardened)

**Document Version:** 1.1.0  
**Date:** 2026-10-21  
**Target Repository:** `https://github.com/davidpovarsky/hanlin-ai`  
**Active Worktree:** `C:\Users\DAVID\Code\hanlin-agent-skills-embedded-results`  
**Target Integration Branch:** `codex/agent-skills-embedded-results` (Head SHA: `aba9f317f93c5ded6b27e1e3f4c89d8c30e5b709`)  
**Dedicated Working Branch:** `codex/classic-chat-native-composer-search`  

---

## 1. Executive Summary & Dual-Baseline Architecture

This document formalizes the exact boundary between two authoritative design sources:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Hanlin AI Chat Interface                       │
├──────────────────────────────────┬─────────────────────────────────────┤
│   Transcript & History Surface   │       Modern Input Composer         │
│   Authority: Commit 478cdd2c     │       Authority: SwiftChat Demo     │
│   (Classic Visual Language)      │       (Multiline Liquid Glass)      │
├──────────────────────────────────┼─────────────────────────────────────┤
│ • Classic message bubbles        │ • Multiline auto-growing text entry │
│ • Classic margins & typography   │ • Real placeholder & text selection │
│ • Stable streaming scroll-follow │ • Native Liquid Glass shell         │
│ • User & assistant action rows   │ • Minimal everyday controls (+/mic) │
│ • Collapsed agent activity steps │ • Contextual/Advanced tools menu    │
│ • Copy, retry, edit, share       │ • Full 278-feature matrix parity    │
└──────────────────────────────────┴─────────────────────────────────────┘
```

---

## 2. Asana Governance & Authorization Gate Status

| Gate Identifier | Asana Task GID | Title | Status | Scope Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Prerequisite MASTER Task** | `1219603005960308` | `[P1] סגירה בטוחה: דוח, branch preservation ואישור שחרור נפרד` | **OPEN (`completed: false`)** | Master regression gate active. |
| **Chat UI & Split Gate** | `1219605282038660` | `[FUTURE 0] שער התחלה — סיום MASTER ואישור נפרד ל-Chat UI ולפיצול MiniApps` | **APPROVED BY OWNER** | **Owner explicitly thawed the 4 frozen files and authorized Phase B execution.** |
| **SwiftChat Composer Task** | `1219605282038884` | `[FUTURE F] Composer SwiftChat-native — multiline Liquid Glass עם כל Hanlin actions` | **IMPLEMENTED** | Native multiline Liquid Glass composer implemented in `ChatViewBottom.swift` with 278-feature matrix parity. |
| **Parent UX Plan** | `1219605220179926` | `[PLAN-2026-10-19-HANLIN-SPLIT-V1]` | **ACTIVE CONTRACT** | Mandates minimal everyday composer; advanced controls in contextual menus. |

> [!NOTE]
> **Owner Authorization Record:**
> Explicit approval was granted by repository owner on 2026-10-21:
> *"מאשר, וכמובן שתבצע את הכל עם macos27 וsdk ios 27, שיהיה תואם לגירסה העדכנית"*
> The 4 frozen UI files were thawed and surgically updated to restore classic transcript presentation while implementing the SwiftChat multiline Liquid Glass composer.

---

## 3. Frozen File Inventory & Planned Surgical Changes

The following 4 files are frozen under repository governance and are awaiting thaw authorization:

### 3.1 `AI_HLY/ChatView.swift`
* **Current State:** 588 lines; manages conversation host, model context, streaming, and downstream presentation policy.
* **Eligible Classic Diff from `478cdd2c`:**
  - Content insets and scroll geometry matching classic visual spacing.
  - Integration of new SwiftChat Liquid Glass composer shell replacing legacy `ChatViewBottom`.
* **Must Preserve:**
  - Downstream presentation hooks: `ChatHostPresentationPolicy`, `ChatPresentationBridge`.
  - Agent event bus, streaming cancellation token, and tool approval sheets.

### 3.2 `AI_HLY/Views/Components/ChatViewComponents.swift`
* **Current State:** Message row rendering, bubble shapes, tool execution indicators.
* **Eligible Classic Diff from `478cdd2c`:**
  - Bubble geometry: classic corner radii, padding, alignment, and background fills.
  - Action row: classic copy, share, retry, edit, and regenerate buttons.
* **Must Preserve:**
  - Interactive embedded result renderers (MiniApps, NativeScript, HanlinScriptUI, rich result cards).
  - Citations and source badge links from web search and knowledge bag.
  - Collapsed intermediate tool steps (`AgentRunTranscriptView`).

### 3.3 `AI_HLY/Views/Components/ChatViewBottom.swift`
* **Current State:** 2,427 lines; legacy monolithic composer with multiple horizontal tool strips.
* **Modern Replacement Target (SwiftChat Full Demo):**
  - Replace with SwiftChat-native Liquid Glass multiline composer (`MessageInputView.swift` at `StreamChatAI-iOS-Demo` commit `13c9a23~1`).
  - Native `CustomTextEditor` bridge: auto-growing height (min 44pt, max 180pt), real placeholder, cursor selection, RTL support.
  - Minimal everyday toolbar: `+` menu (Photos, Files, Camera), microphone, Send/Stop button (`.glassEffect(.regular.interactive(), in: .circle)`), selected model pill.
* **Must Preserve (278-Feature Matrix Parity):**
  - Pasted images, text, and files.
  - `@model` suggestions, drafts, and temporary chat mode.
  - Document/image/link strips and attachments-only sending.
  - Contextual access for Search, Think, Knowledge, Tools, MCP, Audio, Planning.
  - Removal of artificial 720pt cap for iPad multitasking / Split View.

### 3.4 `AI_HLY/ListView.swift`
* **Current State:** Conversation list, search bar, folder management.
* **Eligible Classic Diff from `478cdd2c`:**
  - Classic row heights, selection highlight, and date grouping typography.
* **Must Preserve:**
  - SwiftData conversation queries and session isolation.

---

## 4. Conflict Register & 2026-10-19 UX Decisions

| Feature / Area | Historical `478cdd2c` Design | 2026-10-19 UX Plan (`1219605220179926`) | Authoritative Resolution |
| :--- | :--- | :--- | :--- |
| **Composer Input Field** | Single-line `UITextField` with fixed height. | Multiline auto-growing editor with real placeholder. | **New UX Wins:** Multiline Liquid Glass composer is a deliberate exception. Old single-line input is NOT restored. |
| **Visible Tool Strips** | Horizontal tool strips permanently visible above keyboard. | Minimal everyday controls; advanced tools tucked into context/advanced menus. | **New UX Wins:** Toolbar shows only `+`, mic, send/stop, model. Tools (Search, Think, MCP) accessible via `+` / Advanced. |
| **Model Selection** | Full tab or large bottom sheet. | Compact header capsule or native menu pill. | **New UX Wins:** Compact model capsule or navigation header menu. |
| **iPad Width Cap** | Unconstrained or historical width. | Remove 720pt cap; adapt dynamically to detail column. | **New UX Wins:** Adaptive width without clipping. |
