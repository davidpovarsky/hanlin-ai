# Tool Call Presentation Truth Table

**Document Purpose**: Define the authoritative rules and behavior for projecting and displaying tool executions in the Hanlin classic chat view.

---

## 1. Deduplication and Identity Rules

| Scenario | Input Event / Step | Previous Buggy Behavior | Fixed Authoritative Behavior | Evidence Test |
|---|---|---|---|---|
| **Two distinct calls with identical output** | `call_a` -> `"OK"`<br>`call_b` -> `"OK"` | Collapsed into a single entry because output text matched. `call_b` was dropped. | Two distinct `ClassicProjectedToolCallEntry` rows created, keyed by `callKey = "\(runID):call:\(callID)"`. Execution order preserved. | `ClassicChatRestorationTests.testDuplicateOutputsDifferentCallsRetainOrderAndIdentity` (#27) |
| **Stream chunk updates for same call** | `call_a` -> `"po"`<br>`call_a` -> `"pong"` | Appended duplicates or created synthetic IDs `stream-0-echo`. | In-place update of `call_a`. Exactly one entry maintained. | `ClassicChatRestorationTests.testComplexToolSequenceAndErrorPreservation` (#28) |
| **Out-of-order completions** | `call_skill` (seq 0)<br>`call_echo` (seq 2)<br>`call_mcp` (seq 1) | Flung into arbitrary order based on completion time. | Maintained sorted by `sequence` and original call index. | `ClassicChatRestorationTests.testComplexToolSequenceAndErrorPreservation` (#28) |
| **Domain tool with `### Instructions`** | `read_document` returns Markdown guide with heading `### Instructions` | Heading and subsequent content stripped indiscriminately. | Sanitization checks `isMetaSkillOrDiscoveryTool`. If `false`, `### Instructions` is retained intact. | `ClassicChatRestorationTests.testDomainToolLegitimateInstructionsHeadingPreserved` (#29) |
| **Meta skill tool (`load_skill`)** | `load_skill` returns SKILL.md body with `### Instructions` | Leaked internal system instructions to user view, or stripped everywhere including modelText. | Model receives full `### Instructions`; user-facing summary strips them cleanly. | `ClassicChatRestorationTests.testDomainToolLegitimateInstructionsHeadingPreserved` (#29) |
| **Failed tool execution** | `mcp__file_write` fails with permission error | Mislabeled as completed or lost error detail. | Retains `.failed` status, displays error icon and truthful `errorDescription`. | `ClassicChatRestorationTests.testComplexToolSequenceAndErrorPreservation` (#28) |
| **Legacy chat without `agentRunJSON`** | Old message with `toolContent = "[calc]\n42"` and `agentRunJSON = nil` | Could crash or display empty area if structured projection assumed non-nil run. | Falls back to rendering `effectiveToolContent` in original accordion. | `ClassicChatRestorationTests.testLegacyToolContentOnlyChatFallback` (#31) |
| **Reopen chat / Persistence round-trip** | Encode `AgentRun` to JSON -> persist -> decode -> reopen chat | Lost ordering or collapsed calls upon reload. | JSON round-trip retains exact sequence, stable IDs, and per-call items. | `ClassicChatRestorationTests.testDuplicateOutputsDifferentCallsRetainOrderAndIdentity` (#27) |

---

## 2. Header and Badge Presentation

| Tool Count | Previous Header Text | Fixed Header Text |
|---|---|---|
| 0 | Hidden | Hidden |
| 1 | `manage_mcp_servers` | `manage_mcp_servers` (actual single tool name) |
| 2+ | `manage_mcp_servers (+1)` (falsely claimed last tool owned previous calls) | Localized: `Tool activity (%lld)` (e.g. `Tool activity (2)` / `פעילות כלים (2)` / `工具活动 (2)`) |

---

## 3. Visual Accordion Structure

- **Container**: Classic `ToggleButton` with original blue border and glass material.
- **Identifier**: `hanlin-tool-content-toggle` preserved for accessibility.
- **Child Presentation**:
  - Structured mode: `ForEach(structuredToolEntries)` rendering per-call rows (`toolCallRowView`).
  - Row elements: Status icon (checkmark / warning / spinner), tool alias in monospace, status badge, compact summary, and expandable full payload/error card.
  - Legacy mode: Single monospaced text view if no `agentRunJSON` is present.
