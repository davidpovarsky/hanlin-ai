# Hanlin Architecture Migrations & Consolidation Record

**Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `codex/agent-skills-embedded-results`  
**Reference HEAD:** `89068b77d8a752a5a3d5c9b7dc48735f665245ec`  
**Execution Date:** 2026-10-05  

---

## 1. Executive Summary

Hanlin is now maintained as an independent fork. This document tracks all architectural consolidations, retired legacy paths, newly authoritative implementations, capability invariants protected, and parity verification evidence.

---

## 2. Migration Ledger

### Migration 01: Remote Agent & Provider Consolidation onto Swift AI SDK (R27)
- **Legacy Path Retired:** Manual request builders (`HanlinChatRequestBuilder`), custom SSE streaming parsers (`HanlinChatStreamParser`), and recursive tool execution loop (`APIManager.processToolCallsRecursive`).
- **New Authoritative Path:** `HanlinAISDKAgentEngine.swift` utilizing `streamText`, `prepareStep`, and provider implementations in `SwiftAISDK` (`OpenAIProvider`, `AnthropicProvider`, `GoogleProvider`, `OpenAICompatibleProvider`).
- **Hanlin Seam Adapter:** `HanlinAISDKToolAdapter.swift` bridges Skills, progressive disclosure, canonical tool authority, AgentActivity, and rich embedded results without duplicating the agent loop.
- **Invariants Protected:** `INV-01`, `INV-02`, `INV-03`, `INV-04`, `INV-08`.
- **Parity Tests:** `SDKAI-01` through `SDKAI-18`, `E2E-G`.

### Migration 02: Single MCP Protocol Stack Authority (R29)
- **Legacy Path Retired:** Any custom JSON-RPC/MCP protocol message parsing or duplicate protocol dispatch.
- **New Authoritative Path:** Official `modelcontextprotocol/swift-sdk` (pinned at 0.12.1).
- **Hanlin Seam Adapter:** `EmbeddedNodeMCPTransport.swift` conforms to `MCP.Transport`, connecting the official Swift SDK `Client` directly to Hanlin's embedded Node.js worker lifecycle and per-chat server registry.
- **Invariants Protected:** `INV-19`, `INV-20`.
- **Parity Tests:** `MCPSDK-01` through `MCPSDK-08`, `E2E-I`.

### Migration 03: Skill Import & Archive Policy Normalization (R02, R03)
- **Legacy Path Retired:** 
  1. False path-escape rejection caused by Foundation `/var` vs `/private/var` symlink differences.
  2. Hardcoded file extension allowlist (`isAllowedSkillFile`).
  3. Fixed 25MB / 1,024 files / depth 16 archive clamps.
  4. Naive `JSONDecoder()` date decoding that erased `preferredToolIDs` and `triggerHints`.
- **New Authoritative Path:** Robust single-destination extraction in `SkillImporter.swift` matching `HanlinPackageCenter`; relaxed archive limits; multi-format date codec supporting ISO-8601 (with fractional seconds) and Foundation epoch timestamps; bulk pack import support.
- **Invariants Protected:** `INV-03`, `INV-04`, `INV-29`.
- **Parity Tests:** `ZIP-01` through `ZIP-22`, `META-01` through `META-16`, `E2E-A`.

### Migration 04: Progressive Discovery & Real Capabilities Enumeration (R05, R07, R08)
- **Legacy Path Retired:** Hardcoded word filtering, 4KB schema clamp, and artificial hidden environment assumptions.
- **New Authoritative Path:** Skill-driven tool exposure via `load_skill` and `tool_search`; canonical tools `list_tools`, `get_runtime_capabilities`, and `manage_runtime_packages`.
- **Invariants Protected:** `INV-04`, `INV-05`, `INV-17`, `INV-18`, `INV-30`.
- **Parity Tests:** `DISC-01` through `DISC-22`, `TOOLS-01` through `TOOLS-04`, `PKGT-01` through `PKGT-12`, `E2E-C`.

### Migration 05: Runtime & Package Policy De-restriction (R09, R11, R12, R14, R15)
- **Legacy Path Retired:** 
  1. `rejectUnsafeSource` word blacklist in `host.mjs`.
  2. `rejectUnsupported` guesswork and lifecycle approval ledger in `package-installer.mjs`.
  3. Strict 23-command allowlist and miniRoot sandbox clamps in `IOSSystemRunner.swift` / `ShellRuntimeService.swift`.
  4. Magic bytes and `.pth`/`.wasm` filename bans in `PythonPackageManager.swift`.
  5. Isolated `clients/<id>` workspace confinement preventing inter-runtime collaboration.
- **New Authoritative Path:** Shared workspace cwd across Python, Node, and ios_system; dynamic command catalog from ios_system; capability-driven runtime selection (Node vs JSC); real packaging workflows with streaming and rollback.
- **Invariants Protected:** `INV-11`, `INV-12`, `INV-15`, `INV-16`, `INV-24`.
- **Parity Tests:** `FS-01..12`, `SH-01..22`, `CMD-01..23`, `JS-01..11`, `PKGT-01..12`, `E2E-B`, `E2E-H`.

### Migration 06: Platform Modernization to Stable Xcode 27 / iOS 27 (MASTER-5)
- **Legacy Baseline:** iOS 26.0 deployment target, Swift 6.0, Xcode 26 CI runner.
- **New Modern Baseline:** iOS 27.0 deployment target, Swift 6.4 (Swift 6 mode), Xcode 27 (`27A266a`) toolchain. Host-only test targets maintain appropriate host OS compatibility without blocking product targets.
- **Invariants Protected:** `INV-34`, `INV-35`.
- **Parity Tests:** `PLATFORM-01` through `PLATFORM-08`, `FINAL-01` through `FINAL-12`.

### Migration 07: Absolute Freeze of Existing Hanlin Chat UI (MASTER-4, R30, R31, R32)
- **Constraint:** Zero third-party chat UI packages or architectural redesigns. Existing `ChatView`, `ChatBubbleView`, `ChatViewBottom`, and all composer controls remain intact.
- **Invariants Protected:** `INV-09`, `INV-10`, `INV-34`.
- **Parity Tests:** `CHAT-01` through `CHAT-55`, `E2E-K`, `E2E-O`.
