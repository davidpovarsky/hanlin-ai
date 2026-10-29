# Runtime auto-lifecycle repair — handoff (2026-10-28)

Base: `codex/expo-nativescript-jsi-hybrid-20261027` at `0504bd660e61a079d4488e10bce14f872fbcc431`.
Branch: `fix/runtime-autolifecycle-20261028` (isolated worktree).

## Intended behavior

- Launch embedded Node automatically once per app process; Python, JavaScriptCore, and Shell initialize on an authorized tool call.
- TypeScript execution depends on an authorized Node capability, not a user-operated engine toggle.
- Transient local HTTP health failures preserve the authenticated Node endpoint and can retry on the next use/foreground cycle.
- A genuine return of the native Node thread is recorded separately. No second `node_start` is attempted in the same process.
- Engine power switches disappear from normal settings. Package management and tool permissions stay available, while runtime health is under Developer / Diagnostics.
- Existing MCP worker policy remains: stop on background; preloaded servers resume on active; other approved/selected servers initialize when queried or called. Tool authorization and installed package approval remain unchanged.

## Physical iPad acceptance — NOT YET RUN

1. Cold launch without opening runtime diagnostics. With existing tool approvals, run real JavaScript, TypeScript, Python, JavaScriptCore and Shell actions.
2. Select an already installed and approved MCP server such as `@modelcontextprotocol/server-memory`, request real tools, call one, then repeat after switching chats.
3. Perform repeated foreground/background transitions, short and longer suspensions; confirm previous tool calls still work without manual runtime activation.
4. Exercise a temporary localhost probe failure while native Node remains alive; verify it does not produce an `appRestartRequired` state and later probes can recover.
5. Exercise confirmed Node thread exit in a controlled diagnostic environment; verify a restart-required state rather than an unsupported second native launch.
6. Verify denied tool/MCP capabilities stay denied, including TypeScript's separate Node execution capability; no bypass or duplicate non-idempotent MCP calls.
7. Inspect `node-runtime.log` and developer diagnostics for any reproducible native crash/termination cause. The screenshots do not establish that cause.

## Evidence and limitations

- Static `swiftc -frontend -parse` for changed Swift source: PASS on Windows Swift 6.3.3 (syntax only).
- `git diff --check`: PASS.
- Existing UI acceptance sources updated to target developer diagnostics and automatic runtime readiness, rather than obsolete power switches. These UI tests were NOT RUN.
- Xcode compilation, GitHub Actions, simulator and physical iPad verification: NOT RUN.
- The native Node one-shot limitation and iPadOS suspension restrictions remain. This patch does not claim an always-running background server.
- No frozen chat/Composer files were edited; the only existing upstream-style UI connection changed is the narrow Settings navigation entry.
