# Session, Operation, Lifecycle, and Cancellation Model

Status: proposed contract; no runtime/session code is changed.

## 1. Session hierarchy

```text
host process
  app session (one launched app presentation/interaction)
    runtime session(s) (native, MCP, future script execution context)
      operation(s) (launch, action, service call, tool invocation, script run)
        provider/runtime child tasks and streams
```

Identity is typed at every level. A `HanlinAppSessionID` cannot be passed where
a `HanlinRuntimeSessionID` or invocation ID is required. Parent IDs are included
in child descriptors/events for correlation and cancellation.

## 2. App session

An app session snapshot contains session ID, app and installed-instance IDs,
launch ID, presentation intent, initial/current route reference, creation and
state timestamps, optional parent/caller, and active child operation counts. It
contains no `AnyView`, `Task`, `ModelContext`, or closure.

Legal states:

```text
created -> activating -> active -> suspending -> suspended -> resuming -> active
                       active/suspended -> closing -> closed
                       activating/active/suspended/closing -> failed
```

`closed` and `failed` are terminal. Close is idempotent, rejects new children,
cancels existing children, waits a bounded cleanup period, emits one terminal
event, and releases presentation/runtime resources.

`NativeAppSession` remains the main-actor live object during cutover. Its adapter
publishes canonical snapshots/events. It is replaced only when the host session
controller provides equivalent UI observation and tracked child-task cleanup.

## 3. Runtime session

A runtime session snapshot contains runtime session ID, parent app session or
provider instance, runtime kind, runtime/compiler/protocol versions, negotiated
features and limits, state, and timestamps. It excludes paths, ports, tokens,
transports, SDK clients, and actor references.

Legal states:

```text
allocating -> preparing -> ready -> executing -> ready
                         ready/executing -> suspending -> suspended -> resuming
                         any nonterminal -> stopping -> stopped
                         any nonterminal -> failed
```

`stopped` and `failed` are terminal. A runtime implementation may expose
`restartRequired` as a failure reason/availability condition rather than an
illegal resurrection of the same session. Restart creates a new runtime session
ID and links `replacesSessionID`.

MCP server lifecycle slots, `MCPClientSession`, transports, Node host connection,
and RuntimeCore service actors remain implementation objects. Their adapters
publish canonical state without altering current start/stop/restart behavior.

## 4. Operation state

All launch, action, permission, service, tool, install/migration, and script
operations share these abstract states:

```text
created -> accepted -> running -> completed
                      |       -> failed
                      |       -> denied
                      |       -> cancelled
                      |       -> timedOut
```

Domains may refine `running` (for example compiling or authorizing) but cannot
invent another terminal result. State transitions occur inside one owning actor
or main-actor controller. Events are emitted after the state mutation so
snapshots cannot lag the event.

## 5. Structured concurrency ownership

- Each session controller owns a structured task group or explicit actor-managed
  child tasks with a documented lifetime.
- A child cannot outlive its parent unless a contract explicitly transfers it
  to another owner and records that transfer.
- Fire-and-forget work is not used for state-changing operations.
- Progress polling tasks, MCP tool-change listeners, termination listeners, and
  provider streams are children of the owning operation/session and are awaited
  or cancelled during cleanup.
- UI-bound state is main-actor isolated. Provider/runtime actors never send
  non-`Sendable` implementation objects across isolation.

The current `Task` maps and lifecycle tasks are acceptable implementation
mechanisms during cutover; this document does not claim they currently satisfy
the full contract without compiler/runtime verification.

## 6. Cancellation

Every cancellable operation has its operation ID and optional
`HanlinCancellationID`. A cancel request contains requester identity, reason,
timestamp, and propagation policy. The acknowledgement is:

- `accepted`: cancellation signal delivered;
- `alreadyTerminal`: terminal outcome won the race;
- `atSafePointPending`: current atomic phase will finish, then cancel;
- `notCancellable`: only for an explicitly declared atomic phase; or
- `unknownOperation`.

Cancel is idempotent. Repeated requests return the current acknowledgement and
do not emit duplicate terminal events. Parent close/revocation/timeout propagate
to all children. Provider cancellation maps to the provider mechanism
(`Task.cancel`, MCP disconnect/call cancellation if supported, RuntimeCore cancel
endpoint, future script cancel envelope), but the canonical terminal result is
determined by the owning actor.

Cancellation is checked before authorization, before each irreversible side
effect, during streaming loops, and between lifecycle actions. Cleanup should
observe cancellation only where safe; mandatory rollback/secret cleanup is
shielded and bounded, then awaited.

## 7. Timeout and deadlines

Requests carry an absolute monotonic deadline plus serialized relative timeout
where needed. The receiving process recomputes its local monotonic deadline and
does not compare wall clocks for execution timeout. Expiry timestamps for grants
remain wall-clock security data.

On deadline:

1. actor records timeout requested;
2. cancellation propagates;
3. provider gets a bounded cleanup grace period;
4. one `timedOut` terminal outcome is emitted; and
5. late provider results are discarded and audited, never applied to UI/model
   continuation as success.

## 8. Streams and ordering

Progress/stream events include session/operation ID, monotonically increasing
sequence, timestamp, event kind, and payload. One producer owns sequence.
Consumers may coalesce progress for UI but audit/wire ordering remains intact.
After a terminal event, later data is protocol violation.

Backpressure is bounded. When a nonessential progress stream overflows, it may
coalesce with an explicit dropped/coalesced count. Result, error, permission,
cancellation, and terminal events are never dropped.

## 9. Suspension, backgrounding, and recovery

App backgrounding does not imply session suspension for every provider. The
host policy decides by execution context and capability. Suspension stops new
operations and either pauses supported runtime work or cancels it. A suspended
session retains no implied permission beyond grant conditions.

Live sessions are ephemeral. If the process terminates, recovery records mark
previously running operations as interrupted; they are not resumed unless the
domain has an idempotency/recovery contract. Current native app sessions and MCP
client sessions are not restored. Install/migration transactions may recover
from explicit checkpoints.

## 10. Errors

Invalid transition, parent closed, session unavailable, feature/version mismatch,
provider lost, cleanup timeout, protocol ordering violation, cancellation, and
timeout are distinct. Implementation localized errors map to safe canonical
errors with subsystem codes and correlation IDs.

## 11. Required tests

- Every legal and illegal state transition.
- Concurrent start/stop/restart and completion/cancel/timeout races.
- Parent app close cascading through runtime sessions and provider tasks.
- MCP connect/tool-list/termination tasks cleaned exactly once.
- NativeAppSession tracked tasks and WindowGroup dismissal parity.
- Node/RuntimeCore cancellation endpoint and late-result discard.
- Install polling cancellation plus commit/rollback safe points.
- Stream sequence, terminal uniqueness, overflow coalescing, and backpressure.
- Background/suspend/resume and process-interruption recovery markers.
- Revocation during network/tool/script execution.

## 12. Adapter deletion criteria

Session/lifecycle adapters disappear only after all session and operation
producers publish canonical state, direct consumers no longer inspect subsystem
task/phase models, parent-child cleanup and terminal uniqueness tests pass, and
no persisted recovery record depends on the old schema. Runtime implementation
actors and host UI controllers remain; only duplicate boundary models are
removed.

