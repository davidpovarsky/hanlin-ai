# Embedded MCP runtime

This downstream-only layer runs trusted JavaScript MCP servers locally inside Hanlin's iOS sandbox. Node.js Mobile is launched once on a dedicated native thread. The loopback host listens on an ephemeral `127.0.0.1` port protected by a random bearer token. Each active MCP server runs in its own `worker_threads` Worker with piped stdin, stdout, and stderr.

Installed is not the same as running. Opening the app or MCP settings loads
metadata only. A selected server starts lazily when a chat requests its tool
schemas or calls one of its tools. A server that is not selected is not
started. “Preload when the app opens” is an optional first-use optimization;
it is not required for chat use.

Entering the background gracefully stops every starting, running, stopping,
or failed runtime slot without changing installed descriptors or chat
selections. Returning to the foreground does not eagerly restart ordinary
servers: the next schema or tool request starts them again. The embedded Node
host itself remains alive and is never relaunched inside the same app process.

Server packages are never app resources. They are selected and installed after app installation into `Application Support/HanlinRuntime/v1/packages/mcp/<UUID>` through Pacote and Arborist APIs. Native addons and arbitrary external executables remain unsupported. Lifecycle scripts are structurally planned by RuntimeCore and require explicit approval before any supported action may run.

Install preview exposes every supported package entry point when a package has multiple bins. Update and reinstall use a staging directory plus an atomic server-directory swap; the prior package remains as a temporary backup until the replacement completes MCP initialization and `tools/list`, and is restored automatically if that probe fails. Manual Start, Stop, Restart, tool refresh, logs, runtime generation, Node status, and preload are isolated in Advanced & Diagnostics.

## Persistence and recovery

Persistent server definitions and ephemeral runtime state are separate. Stop,
Restart, backgrounding, cancellation, health failures, and Worker exits never
remove an installed descriptor. Only explicit uninstall or rollback of an
installation that was never committed may remove one.

`MCPServerRegistry.json` and `MCPServerRegistry.backup.json` contain a
versioned document and monotonically increasing generation. Legacy direct
arrays remain readable and retain the `autoStart` storage key. Loads select
the highest valid generation and repair a missing, corrupt, or older peer.
Two corrupt copies produce a typed persistence failure instead of an empty
server list. Saves round-trip-decode before an atomic backup-first,
primary-second replacement, so at least one verified copy remains available.

The installed package root is derived from the stable server UUID under
`Application Support/HanlinRuntime/v1/packages/mcp`, never trusted from an
absolute registry value. Entry points persist a validated package-relative
path. On load and before Start, legacy descriptors from `HanlinMCP/servers`,
older app-container UUIDs, and the former nested `package` layout are migrated
idempotently and saved before Node receives a configuration. Missing or unsafe
installations remain registered and selected, but enter a typed repair-required
state instead of being started.

## Lifecycle and process policy

Each server ID has one actor-isolated lifecycle slot, one generation, and one
shared lifecycle task. Start, Stop, and Restart calls join or serialize behind
that task; stale callbacks are ignored by generation. A server becomes
`running` only after transport connection, MCP initialize, tools/list, and
catalog registration. Stop keeps the slot in `stopping` until client,
transport, event stream, Worker, and catalog cleanup complete.

The Node host mirrors the state machine with one Worker per server ID,
generation-checked map removal, one stop promise, and one finalizer. It closes
stdin first and waits three seconds for a graceful exit. Only a still-live
Worker is terminated, through the same lifecycle path. HTTP lifecycle tests
record creation, maximum concurrency, graceful stop, forced termination, and
finalization counters.

Importing `child_process` is allowed in ESM, CommonJS, dynamic imports, and
`process.getBuiltinModule`. Imports are recorded as module edges and may
produce a compatibility warning. Calling `spawn`, `exec`, `execFile`, `fork`,
their synchronous forms, `_forkChild`, or `ChildProcess.prototype.spawn`
produces a `reachable_external_executable` policy event and throws
`MCPRuntimePolicyError` without terminating the Node host.
`process.binding('spawn_sync')` and the equivalent internal `process_wrap`
capability remain directly blocked. `cluster`, native addons, and external
executables remain unsupported.

See [MCP_LIFECYCLE_INVARIANTS.md](../../../docs/hanlin-platform/MCP_LIFECYCLE_INVARIANTS.md) for the exact
state and ownership rules.

The shared runtime uses embedded Node 24.5.0. Host dependency and TypeScript versions are exact in `RuntimeDependencies.lock.json` and `Downstream/RuntimeCore/Node/Host/package-lock.json`.

## Build preparation

Run `bash Scripts/Runtime/prepare-runtime-core.sh`. The script downloads the immutable verified RuntimeCore release, installs the excluded Node and Python XCFrameworks, and stages the single shared `AI_HLY/RuntimeHostResources.zip` app resource.

## Upstream touchpoints

| Upstream file | Exact modification | Why unavoidable |
| --- | --- | --- |
| `AI_HLY/SettingsView.swift` | One navigation link in Tools | Opens the separate MCP settings UI |
| `AI_HLY/Views/Components/ChatViewBottom.swift` | One separate MCP selector button beside the existing tool button | Provides per-chat server selection without replacing native tools |
| `AI_HLY/ChatView.swift` | Creates one immutable request scope and passes it with the request | Prevents global mutable current-chat state |
| `AI_HLY/Services/ChatServices/APIManager.swift` | Threads the scope, obtains schemas/presentation through `AssistantToolBridge`, and uses its native-first execution fallback | Connects dynamic tools at the existing narrow tool-call points |
| `AI_HLY/AI_HLY.swift` | Small scene lifecycle forwarding hook | Delivers the initial scene phase and later background/foreground transitions |
| `AI_HLY.xcodeproj/project.pbxproj` | Exact SPM products, runtime framework link/embed, Python processing phase, and Host source exclusion | Required compiler/linker/resource wiring |
| `AI-HLY-Info.plist` | Allows loopback-only local networking | Required for the authenticated private HTTP control plane |
| `.github/workflows/build-ios26-unsigned-ipa.yml` | Runs the deterministic bootstrap before Xcode inspection/build | Restores excluded binary and host bundle on the clean macOS runner |
