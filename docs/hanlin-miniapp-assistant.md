# Native assistant API for active MiniApps

The AI application now supplies one session-bound assistant service to the original Expo and NativeScript Host Services adapters. The shared MiniApps runtime depends only on the service protocol. A host without AI composition reports that assistant services are unavailable.

## Public API

Expo uses the existing public package:

```ts
import {hostServices} from '@hanlin/expo-ui';

const models = await hostServices.assistant.models();
for await (const event of hostServices.assistant.stream({
  model: models[0]?.id,
  conversationID: 'document-review',
  system: 'Review the supplied document.',
  messages: [{role: 'user', content: 'Summarize this text…'}],
})) {
  if (event.type === 'text') appendText(event.text);
  if (event.type === 'finish') {
    console.log(event.usage.cachedInputTokens, event.usage.cacheWriteTokens);
  }
}
```

NativeScript uses the original generated package and captures its native session once:

```ts
import {createHostServices} from '@hanlin/host-services';

const host = createHostServices();
const result = await host.assistant.generate({
  messages: [{role: 'user', content: 'Return a short summary.'}],
  responseSchema: {
    type: 'object',
    properties: {summary: {type: 'string'}},
    required: ['summary'],
    additionalProperties: false,
  },
});
console.log(result.value);
```

The model selector is the UUID returned by `models()`, referencing the original Hanlin model row. It accepts no endpoint or API key. Omitting the selector uses the original default-model ordering among enabled, configured providers, with the available Apple on-device model when no eligible remote default exists.

`start()` returns a native request handle, one async event consumer, and explicit `cancel()`. `stream()` also accepts an AbortSignal-compatible object. Breaking a `for await` loop cancels the producer. `generate()` collects only the current generation's text, reasoning, source annotations, final JSON value and usage.

Message content supports text or an array of text and user image parts. Images are HTTPS URLs or base64 bytes with an image media type. Actual model capabilities remain authoritative.

## Native path and authority

1. Each foreground, embedded-result, assistant-tool, and supported headless runtime constructs its own original Host Services adapter.
2. The AI composition injects a service factory into that adapter, using its host-created application, installed-package and session context.
3. The service admits `assistant.models/start/next/cancel` through the existing Host Services capability authority.
4. The model resolver reads the existing SwiftData model/provider records and protected credential registry.
5. The original `HanlinAISDKAgentEngine` performs provider selection, streaming, retries, caching policy and cancellation. The Apple provider is injected through its existing factory.

The model receives an empty tool list and one generation step. This API does not delegate host tools, loaded skills, permission grants, memory, or a conversation transcript. An assistant-tool MiniApp may invoke this API only as its own session-bound generation; that does not transfer the outer agent's tool authority.

Before every HTTP attempt, admission rechecks both the live and durable original provider identity, credential generation, endpoint, dialect, model identity, visibility and caching policy. It also checks the session's revocation lease. A provider edit or adapter teardown invalidates future admission.

## Cache and structured output behavior

The original per-model prompt-cache policy is forwarded unchanged. System instructions remain a distinct system block with one explicit stable boundary. Cache scope includes the host-created MiniApp/session identity, optional conversation identifier and prompt version; the provider layer hashes it together with provider/model identity. No credential is a cache-key component.

Cache reads and writes remain separate optional usage counters. An absent provider counter remains absent. Local metadata telemetry uses the existing diagnostics setting and the original OpenTelemetry adapter; diagnostics off supplies no telemetry and no remote exporter is configured here.

Schema requests use Swift AI SDK's original `Output.object` contract. The native service additionally compiles the retained original schema with `HanlinHostSchemaValidation`, rejects unsupported/external schema references, and validates the completed original JSON plus its JavaScript projection. It never exposes partial structured JSON. A non-stop finish, invalid schema value, malformed JSON or lossy number conversion rejects the structured result.

The Apple on-device provider currently accepts text only. Schema and image requests against it fail explicitly without cloud fallback. Remote schema support still depends on the selected provider/model; a remote listing means the native schema path is available, not that every provider accepts every schema keyword.

Transient bridge payloads and queued output have an 8 MiB memory budget. The existing exact schema validator's 1 MiB schema/result parsing budget also applies. These are memory/parsing bounds; there is no response reuse cache or additional model token quota.

## Source and validation ownership

- Shared service contract: `AI_HLY/Downstream/HostServices/Core/HanlinMiniAppAssistantService.swift`.
- AI-only composition and resolver: `AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppAssistantAIService.swift`.
- One shared TypeScript implementation: `Packages/HanlinExpoUI/src/miniapp-assistant.ts`.
- NativeScript declarations and runtime module are generated together by `Scripts/NativeScript/build-host-services.mjs`.
- Focused Swift suites: `HanlinMiniAppAssistantIntegrationTests` and `HanlinAISDKJSONOutputTests`.
- JavaScript coverage exercises cancellation during admission and pending reads, consumer break, single-reader ownership, schema wire preservation, provider errors and captured NativeScript sessions.

The frozen standalone Scripting-JSC assistant adapter is not the implementation of this active-engine API. Live provider acceptance and native simulator/device acceptance remain separate from source/fixture checks.
