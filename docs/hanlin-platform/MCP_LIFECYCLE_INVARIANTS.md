# Downstream MCP lifecycle invariants

## Ownership

- The registry owns installed definitions; lifecycle code never deletes or
  rewrites them.
- `MCPRuntimeController` owns one runtime slot per server ID.
- A slot owns at most one client session, transport, tool-change task,
  lifecycle task, and active generation.
- `MCPClientSession.disconnect()` owns SDK disconnect. The pinned MCP Swift SDK
  calls `Transport.disconnect()` itself, so the session does not call it a
  second time.
- The Node host owns one Worker state and one finalizer per server ID and
  generation.

## State transitions

```text
stopped ──ensureRunning──> starting ──initialize + tools/list──> running
   ^                           │                                  │
   │                           └──failure──> failed               │
   │                                                              │
   └──────── completed cleanup <── stopping <── stop/restart ─────┘
```

Restart is one lifecycle operation. While it runs, additional Restart calls
join it and Start waits. Each new start increments generation. Exit,
notification, and tool-list callbacks mutate state only when their generation
still matches the slot.

## Shutdown order

1. Mark `stopping` before suspension.
2. Cancel the tool-change task.
3. Ask the MCP client to disconnect.
4. The client disconnects the transport once.
5. The transport cancels and awaits its event stream.
6. The transport sends one host Stop request.
7. The host ends Worker stdin once and waits three seconds.
8. If the Worker remains alive, the host terminates it once.
9. The single finalizer closes event clients, removes listeners and buffers,
   and deletes the map entry only when it is still the same state object.
10. The controller removes catalog entries and publishes `stopped`.

## Scene and Node host lifecycle

The first scene phase is handled immediately after shared application
preparation. Repeated scene events are serialized and deduplicated. Active
loads persistence and optionally preloads opted-in servers. Background awaits
`stopAll()`. Inactive performs no shutdown.

The native Node host has one shared launch task and is started at most once per
app process. A cancelled health check preserves the connection. Non-cancelled
failures receive bounded verification before an already-launched host can be
classified as requiring an app restart.

## Registry durability

- Current schema: `MCPServerRegistryDocument` version 1.
- Legacy `[MCPServerDescriptor]` decodes as schema 0, generation 0.
- Critical identity and executable fields remain required.
- `autoStart` remains the persisted key; `preloadOnLaunch` is only a semantic
  alias.
- The higher valid generation wins, including an intentionally empty registry
  produced by uninstall.
- A load failure preserves the in-memory server list and blocks automatic
  persistence until an explicit retry succeeds.
