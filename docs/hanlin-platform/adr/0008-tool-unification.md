# ADR 0008: Tool unification

Status: accepted
Date: 2026-07-23

## Decision

Built-in native tools, native module tools, script tools, MCP tools, runtime
developer tools, and future intent adapters feed one typed tool registry and
policy pipeline. Existing `NativeTool` and MCP tools migrate through adapters.

Enablement, capabilities, approval, cancellation, progress, diagnostics, and
result presentation are common. `NativeUIBlock` remains compact chat result
UI; it is not expanded into ScriptUI.

## Consequences

MCP protocol behavior remains in MCP while owner identity and operation policy
move to the kernel. Tool profiles remain conversation/provider scoped, and MCP
annotations never remove human confirmation for sensitive actions.
