# Torah Photo Study — Baseline Report

**Date:** 2026-10-05  
**Target Environment:** iOS 17+ / macOS 14+ / Windows Workstation (swift-6.3.3)  
**Authority Layer:** `davidpovarsky/apple-devtools`  

---

## 1. Pinned Starting Points

| Repository / Package | Base Branch | Pinned Base SHA | Active Working Branch | Working SHA | Upstream Model |
|---|---|---|---|---|---|
| `davidpovarsky/hanlin-ai` | `codex/agent-skills-embedded-results` | `da8b729bc4ab477375499e192fcb6b2cb1af3755` | `feat/torah-photo-study` | `e6e222beecbb87be8a98059f143c7b3ddb297bcf` | Independent Fork |
| `davidpovarsky/Maktabah` | `fix/maktabah-search-detail-unification` | `d2fe534f7dfd8bf14a183c93b9926dd394fb4d9f` | `feat/torah-photo-study-bridge` | `9df51ca0b74a387cf3d3b73ebf18c8188172c72b` | Minimal Upstream Touch / Adapters |
| `davidpovarsky/TorahInspectorKit` | — | `b8f71e084bcaa1c60a8e3583034328830aa27fb5` | — | — | Upstream dependency of Maktabah |
| `Packages/TorahLibraryKit` | (new shared package) | — | `feat/torah-photo-study` | — | Single authoritative core |

---

## 2. Baseline Status Analysis

### 2.1 Hanlin Baseline Failure Analysis (Run 37356268858)
The initial CI run on `da8b729bc4ab477375499e192fcb6b2cb1af3755` failed during the full iOS Simulator compilation stage.
- **Root Cause:**
  1. `HanlinSkillCatalog.synchronizeProductionSkills`: Compiled MiniApp and scripting package loaders treated `.resource` entries and then unconditionally returned `# title\n\nsummary`. Because `loadInstructions` gives priority to the loader over `.inline` instructions, any `.inline` instructions were dropped.
  2. `MCPClientSession` was coupled strictly to `EmbeddedNodeMCPTransport`, which forced Node.js runtime initialization even for remote endpoints and prevented pure HTTP transport without Node processes.
- **Remediation:**
  - Preserved `.inline` instruction loading in `HanlinSkillCatalog.swift`.
  - Generalized `MCPClientSession` and `MCPServerLifecycleSlot` to accept `any Transport`, permitting `HTTPClientTransport` directly.
  - Remote MCP servers bypass `runtime.ensureRunning()`.

### 2.2 Maktabah Baseline Status (Run 37329746615)
- Signed build succeeded cleanly on `d2fe534f7dfd8bf14a183c93b9926dd394fb4d9f`.
- Maktabah was lacking inter-app deep link routing for Torah study (`maktabah://study` and `itorah://study`).

---

## 3. Worktree Isolation Policy
To honor user instruction:
> *"שים לב לעבוד בסביבת עבודה נפרדת מהעבודה הנוספת שאני מקיים איתך בינתיים"*

Dedicated git worktrees were created outside the main workspaces:
- Hanlin: `C:\Users\DAVID\Code\hanlin-torah-photo-study` (`feat/torah-photo-study`)
- Maktabah: `C:\Users\DAVID\Code\maktabah-torah-photo-study` (`feat/torah-photo-study-bridge`)

Main directories `C:\Users\DAVID\Code\hanlin-agent-skills-embedded-results` and `C:\Users\DAVID\Code\Maktabah` remain completely untouched.
