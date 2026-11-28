# Public original MCP administration and conversation selection

`HanlinApplicationContext.mcp` exposes the original Hanlin MCP provider without mounting the settings or chat UI. Import `AI_Hanlin` from product `HanlinApplication`. The facade retains its context, and every facade shares the same original process-owned provider, registry, Keychain environment writer, installer and Node/MCP lifecycle. It does not create another registry, tool adapter, runtime or conversation selection store.

## Read and observe the original services

~~~swift
let mcp = context.mcp
try await mcp.load() // Original persistent load; does not start Node.
let installed = mcp.servers
let runtime = mcp.runtime
let currentStatuses = mcp.statuses
~~~

`servers`, `statuses`, `configuration`, `runtime`, `installState`, `persistentLoadState`, `lastError` and `isPerformingAdministration` read the original provider's observable properties. A SwiftUI host can observe these getters. The public server/compatibility/tool/preview value types are the original types, with externally read-only installed metadata. Secret references remain references; listing the registry does not resolve Keychain values. Non-secret environment values remain original metadata.

A failed persistent load throws. Use `load(retryFailedLoad: true)` only when the underlying storage issue has been addressed. Administration methods return their request's actual result or throw its error; a caller does not infer success from the mutable UI `lastError`.

## Configure, install and control

~~~swift
try await mcp.setEnabled(true)
let spec = try MCPPackageSpec("@scope/original-server@1.2.3")
let preview = try await mcp.preview(spec)
let server = try await mcp.install(spec, entryPointOverride: nil)

var settings = MCPServerSettings(server: server)
settings.displayName = "Reader tools"
settings.arguments = ["--workspace", hostWorkspace.path]
let updated = try await mcp.updateServer(server.id, settings: settings)

try await mcp.updateEnvironment([
    MCPEnvironmentDraft(name: "API_TOKEN", value: hostCredential, isSecret: true)
], for: updated.id)
try await mcp.start(updated.id)
let tools = try await mcp.tools(for: updated.id)
~~~

The example package is illustrative, not a recommendation or a package installed by the SDK. The original parser also accepts original supported remote/local `.tgz` sources. Preview, archive validation, compatibility checks, install transaction, protected environment persistence and runtime validation use the existing implementations.

`replacePackage(id, latestCompatible: false)` repairs/reinstalls the currently installed exact version; `true` follows the original update policy. `refreshTools`, `restart`, `stop`, `uninstall` and `setDebugLoggingEnabled` expose their original services. Tool descriptors retain exact input-schema bytes and the original verification, approval and rich-presentation metadata. They are metadata, not grants of tool execution authority.

A settings snapshot captures its installed package identity. The original registry applies editable fields to its current row, preserving current protected environment references. If the installed package changed, saving the old snapshot throws `installationChanged`; reload the actual server and construct new settings. Original entry-point/path validation still occurs in the original runtime.

Environment drafts use the original writer: new Keychain references are staged, the actual registry commits and is read back, and only unreachable old references are removed. An empty secret draft retains its current reference, matching the original editor. Duplicate normalized names are rejected before staging. Already-persisted duplicate environments produce a controlled runtime error instead of a `Dictionary(uniqueKeysWithValues:)` process trap.

## Select servers for one actual conversation

~~~swift
let selected = try await mcp.selectedServers(for: conversationID)
try await mcp.setServer(server.id, selected: true, for: conversationID)

// The same selection is used by the original UI and the headless engine.
let controller = try context.conversationController(conversationID)
let updates = try controller.send(.init(
    text: userText, modelRecordID: model.id, tools: true
))
~~~

The facade validates the actual conversation in its retained context before and after asynchronous operations. Selection changes use the original atomic intent writer and original per-conversation observation. An absent selection uses original defaults; a persisted empty selection stays empty. Other conversations and concurrent selection intents are preserved. Selecting a UUID is a preference, not permission to execute tools: original current eligibility, host consent and run authority still apply.

An unreadable or duplicate-identity selection store no longer restores default MCP authority. The original request scope records the error and supplies an empty, disabled MCP scope. Original registry decoding also rejects ambiguous duplicate server identities.

## Administration ownership and cancellation

One original provider admission covers installation/replacement, lifecycle-changing tool discovery, configuration, environment/settings changes and uninstall through their final recovery/readback. Overlapping administration throws `operationInProgress`; hosts can disable corresponding controls while `isPerformingAdministration` is true. This prevents a replacement from restoring an old, already-removed credential reference or resurrecting a concurrently uninstalled server.

`cancelInstall()` stays outside that admission. A cancellation before the installer has reported its first operation ID is retained for the correct installation and prevents the first runtime action. Later original progress IDs receive that same cancellation. Late progress or cancellation from a completed installation cannot rewrite a newer one's state. Failures restoring the package, registry or previous server are returned as explicit recovery failures. A durable completed installation is not reported as rolled back because of a later cancellation.

Foreground optional preload uses the same admission and its own lifetime token. Backgrounding invalidates pending preload before checking the original OS continuation. Original background stopping remains responsive and does not wait for or steal another operation's admission; in-flight user work retains its original continuation policy.

## Verification boundary

The new public Foundation-only MCP models were type-checked together using Swift 6 without substitute types; changed Swift sources passed syntax checks. Independent review identified and corrected the credential replacement, stale entry-point, foreground-preload, early-cancellation, rollback-reporting and duplicate-environment defects described above.

`HanlinMCPEmbeddingTests` contains ten focused native cases using the original isolated file stores/provider and controlled admission timing. They cover persisted/default/explicit-empty selection, foreign/deleted conversation acknowledgements, real read/write failures, stale package settings, disabled lifecycle, overlapping administration, early cancellation and duplicate identity/environment failures. These cases require their actual Apple execution; no native PASS is claimed by this source receipt.

The existing actual transport test in `RuntimeAutonomyV3Tests` changes only to acknowledge the now-throwing original configuration constructor; its transport, large-result, renderer and persistence assertions are preserved. The full native gate must also retain its original source/runtime binding.
