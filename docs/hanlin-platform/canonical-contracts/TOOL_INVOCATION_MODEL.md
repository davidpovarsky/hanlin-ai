# Tool Identity, Catalog, Routing, and Invocation Model

Status: proposed contract; current native/MCP behavior is unchanged by this work.

## 1. Logical identity

The canonical identity is:

```text
HanlinLogicalToolID {
  providerInstanceID: HanlinProviderInstanceID
  localToolID: HanlinToolID
}
```

Provider examples are conceptually:

- native system tools: provider `native`, instance `native.system`;
- native app tools: provider `native`, instance `native.app.<app-id>`;
- MCP tools: provider `mcp`, instance derived from the durable installed MCP
  server/provider-instance ID;
- future script tools: provider `script`, instance derived from the installed
  script package/app instance.

`localToolID` is stable within the provider instance. `descriptorRevision`
binds a request to the schema that was shown to the model. Display name,
provider slug, server display name, source app title, and model-facing name are
metadata, not identity.

All canonical identities are provider-qualified. There is no permanent global
bare-name identity.

## 2. Model-facing aliases and current behavior

Models require a function name, so each immutable request scope contains a
`HanlinToolRoutingTable` mapping alias to logical identity and descriptor
revision.

During cutover:

- enabled native tool aliases remain their current bare canonical names;
- native registration continues to reject duplicates and invalid names;
- native aliases are inserted first and retain current native-first lookup;
- MCP aliases remain `mcp__<server-slug>__<tool-slug>` with the current
  deterministic length cap/hash collision suffix;
- collision between two MCP instances is resolved deterministically from the
  durable provider-instance ID plus original tool name, never discovery order;
- a future script alias uses reserved `script__<package-or-app-slug>__<tool>`;
- aliases beginning `mcp__` and `script__` are reserved from native registration;
  the current native `app_` restriction may be retired after settings migration,
  but not reused for provider routing.

If any two logical tools still claim the same alias after deterministic
qualification, catalog construction fails for the later conflicting alias and
emits a collision finding. It never silently overwrites a route. The descriptor
may remain visible under its fully qualified fallback alias.

The routing table is captured with the model request. Tool calls from that
request are resolved against that exact table even if live discovery changes.
A removed/unavailable provider then returns `provider_unavailable`; it does not
reroute the alias to a different tool.

## 3. Descriptor and catalog

`HanlinToolDescriptor` evolves to contain:

- logical ID and descriptor revision;
- title/summary and provider/source metadata;
- lossless input and optional output schema documents;
- capability/scope declarations and risk;
- execution contexts and availability;
- idempotency/cancellation/progress characteristics;
- declared resource limits; and
- portable presentation hints only.

Executable closures, `ModelContext`, MCP SDK clients, live actor references,
raw `[String: Any]`, and `NativeUIBlock` do not enter the descriptor.

The canonical catalog actor composes provider snapshots. NativeToolCatalog and
MCPToolCatalog remain provider/executor registries during cutover. A future
ScriptToolCatalog is another provider, not a new global architecture.

Catalog enablement is configuration keyed by logical ID. Existing native
`toolEnabled.<bare-name>` and `toolGroupEnabled.<app-id>` values migrate once to
provider-qualified keys, retaining current values and defaults. MCP request
selection remains request-scoped and is an availability filter, not identity.

## 4. Invocation request

`HanlinToolInvocationRequest` includes:

- invocation ID and optional idempotency key;
- logical tool ID, alias used, descriptor revision, and routing-table revision;
- caller subject, execution origin, app/runtime session IDs, and model round;
- canonical arguments plus proof of input-schema validation;
- permission request/effective-grant references;
- deadline and output/resource limits;
- presentation request as non-authoritative UI intent; and
- trace/audit correlation IDs.

The executor rejects stale schema revision, unknown alias, scope mismatch,
unavailable/disabled provider, invalid arguments, or denied permission before
running provider code.

## 5. Lifecycle and concurrency

```text
created -> accepted -> authorizing -> executing
                               |         |
                               |         +-> completed
                               |         +-> failed
                               |         +-> cancelled
                               |         +-> timedOut
                               +-> denied
```

- One structured task owns one invocation and its provider child tasks.
- Progress events carry invocation ID and monotonically increasing sequence.
- Exactly one terminal result is emitted.
- Cancellation is idempotent. Acknowledgement reports accepted,
  already-terminal, or non-cancellable-safe-point.
- Timeout requests cancellation, waits a bounded provider cleanup interval, then
  records timed out even if an implementation must later finish cleanup.
- Provider catalog refresh cannot mutate the captured route.
- Result-size limits are enforced before UI/activity persistence and model-loop
  continuation.

## 6. Result model

`HanlinToolInvocationResult` has a terminal `HanlinToolOutcome`:

- `completed`: validated canonical result value/content;
- `failed`: `HanlinPlatformError`, including provider `isError` results;
- `denied`: policy/permission decision reference and safe reason;
- `cancelled`: cancellation ID and stage;
- `timedOut`: deadline and cleanup state.

Content is a portable list of text, image/audio/blob attachment descriptors,
resource links/resources, and structured values. Large/binary payloads use
bounded attachment handles. Presentation attachments are separate from the
model result and may be projected to current `NativeUIBlock` during cutover.

Current `NativeToolResult.modelText`, `userText`, and `uiBlocks` are produced by
a presentation/activity adapter. Current MCP text/image/audio/resource content
maps to canonical content before that projection. String descriptions are not a
fallback for unsupported MCP cases.

## 7. Provider adapters

### Native

The native adapter converts canonical arguments to the existing JSON string,
invokes the existing `NativeTool` on the main actor, and converts
`NativeToolResult`. Until native tools accept canonical requests directly, the
adapter must prove schema and value conversion is lossless. Existing execution
enablement and UI behavior remain unchanged.

### MCP

The MCP adapter resolves the provider instance, converts canonical JSON object
arguments to the pinned MCP SDK `Value`, calls the original MCP tool name, and
maps typed content/`isError`. It retains current server selection, lazy start,
tool-list refresh, collision aliases, and failure reporting.

### Future script

A script tool adapter exists only after compiler/runtime/permission gates. It
uses the same invocation/result/cancellation contracts and cannot bypass policy
because a declaration calls itself an assistant tool.

## 8. Error and collision semantics

Stable categories include invalid descriptor/schema, alias collision, stale
route/descriptor, disabled tool, provider unavailable, invalid arguments,
permission denied, provider rejected, transport failure, provider execution
failure, invalid result, output limit, cancellation, and timeout.

Native errors no longer need to be inferred solely from a UI error block after
the provider adopts canonical results. During cutover the adapter retains that
legacy inference and marks it as legacy-derived in diagnostics.

## 9. Required tests

- Exact snapshot of current native aliases, order-independent registration, and
  duplicate rejection.
- Exact MCP name codec/collision/64-character behavior using durable instance
  IDs, including same slug/name from multiple servers.
- Native-first resolution for every current observable collision scenario.
- Frozen request scope despite enablement/discovery changes.
- Native, MCP text, image, audio, resource, link, empty, and error results.
- Invalid/oversized arguments and results; unknown schema keyword projection.
- Cancellation before authorization, during provider start, during call, after
  terminal completion, and timeout/cleanup races.
- MCP server removal/restart/tool-list change during an invocation.
- Settings migration for native aliases/groups and MCP chat selections.
- Activity/transcript/presentation parity and model-loop continuation parity.

## 10. Adapter deletion criteria

`AssistantToolBridge`/provider adapters may be deleted or reduced only after all
model schema assembly and call execution use captured canonical routing tables;
native and MCP providers directly accept/return canonical contracts; legacy
settings are migrated; persisted activity/UI data retains a reader; all tests
above pass; no direct APIManager lookup path remains; and owner-approved Xcode
verification succeeds on the exact commit.

