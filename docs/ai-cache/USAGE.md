# Using Hanlin cache policies and diagnostics

Source review: **2026-11-25**, integration baseline `168d8cd62f30440449b192d9d66cc4cd21b38657`. The signatures below were checked against that source. The examples were not executed against a live provider. Core, native app and UI acceptance remain pending until the integration owner records their results; existing narrower evidence is listed below.

See the [execution plan](PLAN_20261125.md) and [architecture/dependency decisions](CACHE_AND_OBSERVABILITY_ADR.md).

## Model and agent preferences in the app

Open a model or editable custom agent in the existing model editor and use **Prompt cache → Cache policy**. Options follow the selected model's provider, API dialect and endpoint.

| Choice | Meaning |
| --- | --- |
| Automatic (recommended) | Store the historical `nil` preference. Hanlin applies supported automatic provider hints; this does not guarantee a hit. |
| Provider defaults | Omit Hanlin's explicit cache controls and use the provider's defaults. |
| No explicit cache controls | Omit Hanlin's cache controls/breakpoints. Provider implicit caching may still occur; this is not a remote-cache purge. |
| Anthropic: 1 hour | Request the supported longer lifetime. Provider eligibility and billing still apply. |
| OpenAI: up to 24 hours | Available only for the documented legacy model families on a native OpenAI endpoint. |
| Explicit cache: 30 minutes / 12 hours | Available for supported modern model families using native OpenAI Responses. |
| Use selected base model policy | Copy the selected base's saved policy into the agent when saved. This is a snapshot, not a permanent link to later base edits. |
| Saved/custom policy (unchanged) | Keep the current serialized policy, including custom settings. |

An unchanged agent base preserves its existing custom policy. A real change of normalized wire model ID or provider inherits the new base policy unless the user makes an explicit policy choice. A new agent copy inherits the selected copy base's policy. Internal `_agent_`, `_repeat_` and `_hanlin` suffixes do not by themselves constitute a different model. Existing unrelated copy/name/capability behavior remains unchanged.

Cache validation happens before the editor changes existing fields. An unavailable explicit selection or invalid scoped resource produces an error and leaves the editor open. Changing the base updates the available choices.

### Native configuration and rollback

The public configuration field is `HanlinChatModelConfiguration.promptCachePolicy`. Supply a `HanlinPromptCachePolicy?` in its initializer; configurations are immutable, so rebuild the configuration when changing this field. For preset-driven callers, use `HanlinPromptCachePreset.available(company:apiType:endpoint:modelID:)` and then the chosen preset's `policy`. Do not infer native OpenAI capabilities from a model name alone.

The app persists the preference in the existing `AllModels` SwiftData row. Its `setPromptCachePolicy(_:)` serializer rejects Google resource references and OpenAI comparison response IDs: these belong to a scoped request, never a global model preference. Existing app configuration, session and compact paths carry the optional policy.

To return to ordinary behavior, select **Automatic**, or pass `promptCachePolicy: nil` when constructing a configuration. To stop Hanlin cache hints, select **Provider defaults** or **No explicit cache controls**. These choices neither delete a Google resource nor prevent provider-managed implicit caching. Existing explicit Google resources require a separate delete or expiry. No database migration, Redis deployment or second model engine is needed for this rollback.

## Google explicit cached content: public Swift API only

This is an **opt-in API in `HanlinChatCore`**. The current application and JavaScript Host contract do not expose a paid-resource creation/renewal/deletion screen. Ordinary app agent conversations continue on the provider's implicit caching path. Calling the manager is the explicit action; normal chat does not create resources as a side effect.

The public entry points are:

- `HanlinGoogleCachedContentManager(configuration:scope:transport:)`, using the existing native credential and the configuration-derived scope key.
- `create(contents:ttl:displayName:)`, `get(_:)`, `updateTTL(_:ttl:)` and `delete(_:)`.
- `HanlinPromptCachePolicy(googleCachedContent:)` plus the same `cacheScope` passed to the native generation call.

This manager deliberately supports **content-only** resources. It rejects unsupported model families, including Gemini 4/Interactions, and restricts its default transport to the original Google generative-language endpoint. The service remains authoritative for exact model availability, minimum content size and charges. Creation and TTL extension may incur storage charges.

### 1. Create a scoped resource

The following snippets belong inside an async native caller. `existingCredential`, `accountScopeID`, `conversationID`, `documentText` and `question` are inputs from the authorized native credential/session owner and the user's content. Keep secrets in that existing native channel; do not pass credentials through JavaScript or put them in source/logs.

```swift
import Foundation
import AISDKProvider
import HanlinChatCore

func contentConfiguration(
    credential: String,
    reference: HanlinGoogleCachedContentReference?
) -> HanlinChatModelConfiguration {
    HanlinChatModelConfiguration(
        modelID: "gemini-2.5-flash",
        company: "Google",
        apiType: "Gemini",
        endpoint: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        apiKey: credential,
        supportsToolUse: false,
        systemPrompt: nil,
        promptCachePolicy: reference.map {
            HanlinPromptCachePolicy(googleCachedContent: $0)
        }
    )
}

let scope = HanlinPromptCacheScope(
    namespace: ["hanlin", "content-cache", accountScopeID],
    conversationID: conversationID,
    promptVersion: "content-only-v1"
)
let uncachedConfiguration = contentConfiguration(
    credential: existingCredential, reference: nil
)
let manager = try HanlinGoogleCachedContentManager(
    configuration: uncachedConfiguration, scope: scope
)
let contents: [JSONValue] = [
    .object([
        "role": .string("user"),
        "parts": .array([.object(["text": .string(documentText)])])
    ])
]
var reference = try await manager.create(
    contents: contents, ttl: 300, displayName: "Conversation context"
)
let referenceData = try JSONEncoder().encode(reference)
```

Persist `referenceData` in the **owning conversation's existing storage** immediately after receiving it; this guide does not introduce another store. Keep the original document and history as well: the reference is metadata, not a replacement for durable content. It contains the resource name, normalized model, expiry, scope key and optional token count, without the corpus or credential.

The configuration-based initializer binds the scope hash to the endpoint, provider, API dialect, wire model, conversation and caller-supplied nonsecret namespace/version. Use an account-specific namespace and change the appropriate scope/version when its identity changes. A scope key is an isolation/routing hint, not an authorization credential. Avoid the low-level `modelID:scopeKey:apiKey:` initializer unless the caller already owns that complete binding.

### 2. Generate using that reference

Use the same account, endpoint, wire model and scope. Send the new question/history that is not already in the cached corpus. For this content-only path, keep `systemPrompt` and `baseSystemPrompt` empty, supply no system-role messages or tools, and omit `dynamicTools`.

```swift
let cachedConfiguration = contentConfiguration(
    credential: existingCredential, reference: reference
)
let engine = try HanlinAISDKAgentEngine(
    configuration: cachedConfiguration,
    fetch: await HanlinChatEngine().makeAISDKFetch()
)
let events = try await engine.stream(
    messages: [.init(role: .user, text: question)],
    baseSystemPrompt: nil,
    tools: [],
    cacheScope: scope,
    prepareStep: { (_: Int) async in
        HanlinAISDKStepPreparation(activeToolAliases: [])
    }
)

var answer = ""
var usage: HanlinChatTokenUsage?
for try await event in events {
    switch event {
    case .textDelta(let text):
        answer += text
    case .finished(_, let reportedUsage):
        usage = reportedUsage
    case .cancelled:
        throw CancellationError()
    default:
        break
    }
}
```

The factory validates the reference's name, model, scope and expiry at the actual turn. It sends `cachedContent` through the original provider path. A valid reference does not prove that a particular request received a cache hit; use the returned provider usage for that observation.

### 3. Refresh, renew and delete explicitly

```swift
reference = try await manager.get(reference)
reference = try await manager.updateTTL(reference, ttl: 600)
// Save the updated reference metadata in the same conversation store.
try await manager.delete(reference)
// Remove the locally stored reference after successful deletion.
```

`get` refreshes metadata. `updateTTL` updates the existing resource; it does not change its contents or recreate a missing resource. To cache different content, create a new resource explicitly and retire the old reference. Successful `delete` includes an already missing/expired resource (HTTP 404/410). It never deletes another conversation's resource.

Cancellation before sending makes no request. After a create request reaches the service, cancellation/transport loss cannot prove that no billable resource was created. The manager does not blindly retry creation. If a successful creation receipt arrives just after cancellation, the manager preserves that receipt so the owner can save it and request deletion. Run requested cleanup from a live owner task; a cancelled task cannot issue the manager's next request. If no receipt arrived, retain the bounded TTL and report the outcome as uncertain rather than claiming deletion or issuing an automatic second create.

### Failure and full-context fallback

| Condition | Required caller behavior |
| --- | --- |
| System instructions or tools are required | Use the ordinary implicit path with the full original instructions, tool definitions, history and content. Do not remove them to make an explicit resource fit. |
| Reference expired or the service reports it missing | Explicitly choose a new resource or an ordinary request without the reference. Re-send the complete source content/history on the ordinary path. |
| Model/account/endpoint/scope mismatch | Reject reuse. Resolve the intended context; never rewrite the old reference's identity to pass validation. |
| Creation, authentication, quota or transport error | Surface the error. Do not assume success, silently retry paid creation, or treat a quota/authorization failure as a reason to bypass controls. |

For this simple content-only example, returning to implicit caching starts with the original document:

```swift
let fallbackEngine = try HanlinAISDKAgentEngine(
    configuration: uncachedConfiguration,
    fetch: await HanlinChatEngine().makeAISDKFetch()
)
let fallbackEvents = try await fallbackEngine.stream(
    messages: [
        .init(role: .user, text: documentText),
        .init(role: .user, text: question)
    ],
    baseSystemPrompt: nil,
    tools: [],
    cacheScope: scope,
    prepareStep: { (_: Int) async in
        HanlinAISDKStepPreparation(activeToolAliases: [])
    }
)
// Consume fallbackEvents through the same native event/UI path.
```

For a real agent, restore **all** original system instructions, tools and history as well. Simply removing `googleCachedContent` while sending only the latest question would lose the cached context. Fallback is an explicit caller decision; this manager does not silently alter a conversation or recreate resources.

## Diagnostics and OpenTelemetry

The existing native agent diagnostics UI shows provider cache reads/writes, per-round coverage and a weighted cache-read fraction when every contributing round has valid reported input/read counts. Missing remains unavailable; a reported zero remains zero. Cache read/write tokens are input components, not extra tokens to add to the total. The fraction is a token reuse measurement, **not a request hit rate or a billed savings percentage**.

App composition passes `nil` telemetry when diagnostics are off. When enabled it uses `HanlinOpenTelemetryTracer.local.telemetrySettings()`, which exports metadata to local OSLog. It does not contact a collector or Langfuse.

For an explicitly configured destination, inject an original `OpenTelemetrySdk.SpanExporter`:

```swift
import OpenTelemetrySdk

// configuredExporter is supplied by the caller's explicit exporter setup.
let tracer = HanlinOpenTelemetryTracer(exporter: configuredExporter)
let tracedEngine = try HanlinAISDKAgentEngine(
    configuration: cachedConfiguration,
    fetch: await HanlinChatEngine().makeAISDKFetch(),
    telemetry: tracer.telemetrySettings()
)
```

Keep `tracer` alive for the operations it observes. After active streams finish, flush at an owned lifecycle boundary with `tracer.forceFlush(timeout: 5)` off the UI path, then call `tracer.shutdown()` when that owned instance is no longer needed. Do not shut down the shared `.local` tracer after each request.

Input/output recording is disabled. The adapter also filters metadata and excludes prompt/completion text, headers, credentials, tool arguments/results and exception details. Original SDK batching is bounded. `HanlinOpenTelemetryTracer()` without an exporter has no export destination; adding this dependency does not configure a network exporter, backend account or credentials. Roll back export by constructing subsequent engines with `telemetry: nil` and closing the owned tracer after its active work finishes.

For totals, choose one span aggregation level and one attribute namespace. Do not sum the same usage from root and child spans, or add both `ai.usage.*` and their `gen_ai.usage.*` aliases.

## Validation and closure boundaries

This guide is **source-reviewed documentation**, not an execution receipt. At its source baseline:

| Evidence | What it establishes |
| --- | --- |
| [Local cache/accounting receipt](evidence/local-cache-20261125/receipt.json) | Previously executed 18-case native proof: 11 local-cache lifecycle cases and 7 accounting cases, with exact source/dependency hashes. Reuse requires unchanged inputs. |
| [Active assistant JavaScript summary](evidence/active-assistant-js-20261125/summary.json) | Previously executed 15 JavaScript contract tests plus generation/drift checks. It explicitly does not certify a native app build. |
| [Canonical graph receipt](evidence/canonical-graph-20261125/receipt.json) | Recorded generator/project-update and check commands for its source SHA. It is not a full app build or a provider call. |
| Core/provider/Google lifecycle/OTel tests and app UI | Await the integration owner's exact-source native acceptance receipts. Authored tests or successful compilation alone are not a test pass. |
| Live provider cache hits, Google resource receipts, storage costs or savings | Not executed by this documentation work. Requires an authorized account and actual provider usage/billing evidence. |

The public Google lifecycle cases live in `HanlinGoogleCachedContentTests.swift`; scoped generation/conflict cases live in `HanlinPromptCacheTests.swift`. Preset and agent inheritance cases live in `HanlinPromptCachePresetTests.swift` and `HanlinPromptCachePolicyMutationTests.swift`. Original producer span assertions and the OTel bridge tests cover separate boundaries.

Live acceptance must record the actual model/API, authorized account scope without secrets, provider request/resource identity, measured usage and cleanup/expiry result. A stubbed resource name, fixture token count, local cache hit, generation success or compiled exporter is not evidence of a provider cache hit or a monetary saving. If an authorized account is unavailable, leave LIVE as `NOT_RUN`/`BLOCKED` with the reason. C7's live receipt and the plan's final acceptance remain distinct from native contract acceptance.

C9 still requires the integration owner to reconcile final source heads, publish the branch/PR, attach exact-source evidence, and update the stage and parent tasks accurately. This guide does not mark those actions complete.

## Source entry points

- [Typed policy and scope](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinPromptCachePolicy.swift)
- [Model configuration](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatModelConfiguration.swift)
- [Preset capability gating](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinPromptCachePreset.swift)
- [Agent policy mutation rules](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinPromptCachePolicyMutation.swift)
- [Native model editor](../../AI_HLY/Views/Components/ModelsViewComponents.swift)
- [Model preference persistence guard](../../AI_HLY/Downstream/ChatCore/HanlinModelPromptCachePreferences.swift)
- [Google lifecycle and reference](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinGoogleCachedContent.swift)
- [Provider option/context validation](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKProviderFactory.swift)
- [Native generation/streaming](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift)
- [OpenTelemetry adapter](../../Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinOpenTelemetryTracer.swift)
