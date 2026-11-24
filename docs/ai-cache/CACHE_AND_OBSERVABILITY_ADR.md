# Cache and observability architecture decision

Status: implementation contract for the November 2026 cache integration. Native build/test evidence is recorded separately against the integration commit; this document does not claim a released app or a live provider cache hit.

Source and maintenance review: 2026-11-24 UTC. Implementation branches use the integration-stage date 20261125.

## Decision

Keep Hanlin's native Swift model execution. Use the original Swift AI SDK for provider request/stream/tool semantics, original LRUCache for bounded reproducible local search results, and original OpenTelemetry Swift API/SDK for the existing model spans. Retain SwiftData and the existing durable tool-result store. A distributed cache, another model gateway, and a remote observability service are separate deployment decisions; none is required to repair native prompt caching.

A provider owns its inference/KV/prompt-cache storage, capacity, retention rules and actual cache hits. Hanlin owns stable request construction, correct provider options, credential/session scoping, accounting, local invalidation, cancellation and measurement. Installing a client-side cache library does not create or control the provider's cache.

## Where each responsibility lives

| Layer | Production source | Responsibility |
| --- | --- | --- |
| Native app composition | `AI_HLY/Services/ChatServices/APIManager.swift`; native MiniApp/session adapters | Pass provider/model, credential scope and diagnostics into native engines. |
| Model execution | `Packages/HanlinPlatform/Sources/HanlinChatCore`; `Packages/HanlinAgentSDK` | Original Swift AI SDK calls, provider options, streaming and tool rounds. |
| Provider accounting | `HanlinChatTokenUsage`, stream parsers and app mappings | Preserve cache reads and writes independently; missing remains missing. |
| Diagnostics | `AI_HLY/Downstream/AgentDiagnostics` | Per-round counts, measured coverage, aggregate read fraction, readable exports and native UI. |
| Telemetry | `HanlinOpenTelemetryTracer.swift` | Real OpenTelemetry spans, task-local parentage, bounded batching and metadata filtering. |
| Search reuse | `AutomaticWebSearchCoordinator.swift` | TTL, original LRUCache count/cost policy, coalescing and cancellation. |
| MCP catalog | `AI_HLY/Downstream/MCP/ToolIntegration/MCPToolCatalog.swift` | Live tool descriptors, stable ordering, per-server replace/remove. |
| Full tool artifacts | `AI_HLY/Downstream/AgentSkills/ToolResultStore.swift` | Disk-backed full results and bounded read slices. Pagination limits transport, not normal retention. |

JavaScript MiniApps call the existing bridge into Swift. This does not require a second JavaScript AI SDK/provider implementation inside the app.

## Dependencies evaluated

| Library or service | Decision | Reason and maintenance evidence |
| --- | --- | --- |
| Swift AI SDK | Keep the original package and narrowly maintained producer fork. | The native execution boundary already exists. Provider options and missing usage fields belong there. The integration manifest pins the reviewed revision. |
| [nicklockwood/LRUCache](https://github.com/nicklockwood/LRUCache) | Add original package, exact **1.3.0**, product `LRUCache`. | Deterministic LRU, count/cost bounds and Apple memory-pressure handling. Tag 1.3.0 is commit `f0570e943ea4445d258113ba73f50cb2b7e564ac`, dated 2026-08-26. Upstream publishes tags rather than GitHub Release records. |
| [Foundation NSCache](https://developer.apple.com/documentation/foundation/nscache) | Alternative for a particular cache, not another layer around LRUCache. | Existing unrelated image/widget/code-fence caches remain. Stacking both for identical search results adds policies and copies without a distinct need. |
| [OpenTelemetryApi and OpenTelemetrySdk](https://github.com/open-telemetry/opentelemetry-swift-core/releases/tag/2.6.0) | Add original products, exact **2.6.0**. | Real span creation, lifecycle, batch processing and exporter injection. No replacement SDK or custom wire protocol. |
| [OpenTelemetry Swift exporters](https://github.com/open-telemetry/opentelemetry-swift/releases/tag/2.6.0) | Optional for an explicitly configured destination. | Stable main 2.6.0 still consumes core 2.6.0. Core development is moving into the main repository; follow that migration on upgrades. Every exporter, gRPC and automatic HTTP instrumentation are unnecessary for local telemetry. |
| [Langfuse](https://langfuse.com/integrations/native/opentelemetry) | Optional compatible backend. | Its documented non-Python/JS path is native OpenTelemetry; OTLP HTTP JSON/protobuf is supported, gRPC currently is not. No account, backend, ingestion key or network destination is installed by this change. |
| [apple/swift-metrics](https://github.com/apple/swift-metrics) | No second instrumentation pipeline. | A backend-neutral metrics API. Current requirements use local cache counters and model traces; add a bridge only for a specific consumer. |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | No new database layer. | A SQLite toolkit, not provider prompt caching. SwiftData and durable artifacts already exist; another database needs a storage requirement and migration plan. |
| Redis / [Valkey](https://valkey.io/) | No new server deployment. | Shared server-side data/coordination requires an actual server use case. A phone should not acquire distributed-cache credentials to improve prompt caching. |
| [RediStack](https://forums.swift.org/t/deprecating-redistack-transitioning-to-valkey-swift/86172) | Do not introduce it. | Maintainers announced deprecation on 2026-04-22 and migration to official Valkey Swift. Earlier recommendations are superseded by this finding. |
| [valkey-io/valkey-swift](https://github.com/valkey-io/valkey-swift) | Evaluate for a future Swift server cache requirement. | Maintained successor, release 1.6.0 on 2026-10-30. Not a native-app requirement here. |
| [LiteLLM](https://docs.litellm.ai/) | No additional proxy/model gateway. | Native routing exists. A gateway adds a separate deployment/security responsibility and does not repair client accounting or provider directives. |
| [Vercel AI SDK](https://ai-sdk.dev/docs/introduction) | No second JavaScript provider stack. | Swift SDK/native bridges execute the app's model calls. JavaScript examples do not justify importing that stack into native Swift. |
| [Official MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | Keep existing integration. | Discovery/notifications belong to MCP. Sorted descriptors support stable request schemas without a separate cache dependency. |

Integrate useful library capabilities at the production path that needs them. Installing unrelated exporters, databases or server clients does not make that integration more complete.

## Local search cache contract

`AutomaticWebSearchCoordinator` owns request policy. Original `LRUCache<String, CacheEntry>` owns storage, recency and capacity eviction.

| Setting | Default |
| --- | --- |
| Freshness lifetime | 300 seconds after successful completion |
| Entry cap | 50 |
| Cost cap | 4 MiB estimated cached payload cost |
| Provider / overall deadline | Existing 4 / 10 seconds |
| Failure caching | None |
| Oversized success | Returned intact, excluded from cache |
| Diagnostic bypass | Independent fresh request; neither joins nor replaces normal cache |
| Invalidation | Clear reusable entries and advance generation |

The byte budget estimates payload cost, not exact process heap consumption. Both limits are enforced; Apple memory pressure may also clear entries through the original library.

Equivalent canonical query/count requests share one provider operation. Every caller retains its own continuation. Cancelling one leaves other waiters running; the final waiter cancels the worker. Cancellation is checked before continuation registration and after awaiting. Flight identifiers stop an old cancelled worker from completing a newer flight for the same key.

Invalidation lets already waiting callers finish while preventing their older generation from serving new callers or repopulating the cache. TTL expires at the exact boundary; clock rollback also invalidates freshness. Lifetime starts at successful provider completion.

`cacheStatistics()` reports hits, misses, coalesced requests, bypasses, expirations, invalidations, capacity evictions, current count/cost and active flight/waiter counts. It contains no queries, result text, credentials or user identifiers. A miss is a caller cache miss; coalesced callers do not imply additional provider requests. Capacity-eviction accounting describes coordinator insertions, not guaranteed counts of external OS memory-pressure removals.

Current adapters perform public search. Authenticated, tenant-specific, locale-sensitive or otherwise parameterized search requires extending key scope before results may be shared across those contexts.

## Native model settings

The existing model editor exposes automatic, provider-default and no-explicit-controls policies. The last label explicitly allows provider implicit caching. Anthropic offers a one-hour option. Native OpenAI HTTPS endpoints offer 24-hour retention only for documented legacy model families; explicit 30-minute/12-hour presets are limited to supported modern families using Responses. Gateways, plan transport and local/on-device models do not acquire those native-provider presets.

The settings helper recognizes the native singular OpenAI-Response dialect as well as its plural SDK spelling. It recognizes documented dated legacy snapshots without assuming every similarly named mini/nano variant supports extended retention. Future major model families require review before paid TTL presets appear.

An untouched custom or historical policy is not rewritten. Selecting automatic deliberately stores the historical nil default. Model preferences expose neither scoped Google resource references nor comparison response IDs. Validation occurs before other model-field edits, and validation/persistence errors remain visible in the editor instead of dismissing as success. Agent copying and unrelated model editing retain their existing behavior.

Five focused preset tests cover migration/custom preservation, old/new OpenAI lifetime differences, Responses restrictions, endpoint/transport boundaries, malformed identifiers and Anthropic/local availability. They are separate from view rendering and persistence verification.

## Provider accounting and native diagnostics

`cachedInputTokens` measures provider cache reads; `cacheWriteTokens` measures writes. They are input-token components, not additional tokens to add again to a total. Provider-normalized reasoning tokens similarly belong within output totals.

Missing measurement is not zero. Older records continue to decode with optional fields absent. `AgentTokenUsage` derives a total only with both input and output unless an explicit provider total exists.

`AgentPromptCacheSummary` reports:

- Measured cache read/write tokens.
- Separate read/write coverage: reported rounds / all rounds.
- Weighted cache-read fraction: total cached input / total input.

The fraction requires valid provider-reported input and read values in every round. Estimated, mixed, missing or inconsistent values suppress it. Genuine reported zero remains visible. This is not a monetary savings percentage; billing depends on provider/model rates, retention mode, token classes and cache creation pricing.

The existing diagnostics UI gains a prompt-cache section and per-round read/write rows. Readable exports carry measurements and coverage. English, Hebrew and Simplified Chinese strings are in the canonical catalog. No second monitoring screen/database is introduced.

## Original OpenTelemetry integration

The Swift AI SDK owns existing `ai.streamText`, request and tool spans. `HanlinOpenTelemetryTracer` adapts them to original OpenTelemetry `TracerProviderBuilder`/`SpanBuilder` instances. It does not add another usage span for the same operation.

Native composition policy:

```swift
let telemetry = AgentDiagnosticsConfiguration.level == .off
    ? nil
    : HanlinOpenTelemetryTracer.local.telemetrySettings()
```

Pass this to the native engine's `telemetry` parameter. Integration must verify main-app, session and MiniApp call sites; a bridge type alone does not enable telemetry.

`telemetrySettings()` explicitly disables `recordInputs` and `recordOutputs`. The adapter also allowlists metadata: bounded provider/model/tool identifiers, known finish reasons, finite generation/timing values and nonnegative token counts. It excludes prompts, output text, stop sequences, headers, arbitrary metadata and tool arguments/results. Error messages/domains/stacks and unknown names are omitted or replaced by fixed categories. It reads no environment credentials and alters no global tracer.

Original batching bounds are 256 queued spans, 64 per batch, one-second delay and five-second timeout. SDK limits bound span attributes/events and attribute lengths. Overflow follows original SDK policy. Task-local immutable contexts preserve parentage across suspension and isolate concurrent requests. Original non-Sendable references stay behind a Swift `Mutex`; no new unchecked Sendable annotations are added.

SDK `recordSpan` owns `end()`. Streaming spans may outlive their active closure; repeated ending is idempotent and subsequent mutations are ignored. Explicit `forceFlush(timeout:)` and `shutdown()` support lifecycle management. End active work before shutdown and flush off the UI path. Exporters must respect timeout and avoid recursively instrumenting export calls.

`HanlinOSLogSpanExporter` logs only local operation name, elapsed milliseconds, input/output/cache read/cache write counts and failure status. Missing count logs `unavailable`. `HanlinOpenTelemetryTracer()` without an exporter has no export destination. Remote reporting requires explicit injection:

```swift
let tracer = HanlinOpenTelemetryTracer(exporter: configuredExporter)
let settings = tracer.telemetrySettings()
// Pass settings to the native engine's telemetry parameter.
```

Keep the tracer alive for the intended scope and own exporter lifecycle. This seam supports a configured collector/HTTP exporter without installing a remote service or credentials as a side effect.

| Original SDK attribute | Current GenAI alias |
| --- | --- |
| `ai.usage.inputTokens` | `gen_ai.usage.input_tokens` |
| `ai.usage.outputTokens` | `gen_ai.usage.output_tokens` |
| `ai.usage.reasoningTokens` | `gen_ai.usage.reasoning.output_tokens` |
| `ai.usage.cachedInputTokens` | `gen_ai.usage.cache_read.input_tokens` |
| `ai.usage.cacheWriteTokens` | `gen_ai.usage.cache_write.input_tokens` |
| `ai.usage.noCacheTokens` | Preserved original; no invented standard alias |

The [current official GenAI registry](https://github.com/open-telemetry/semantic-conventions-genai/blob/main/docs/registry/attributes/gen-ai.md) uses `cache_write`; older general conventions used `cache_creation` before the registry moved. Detailed counts are subsets of totals. Dashboards must choose one attribute namespace and one span aggregation level: never sum aliases or parent/child usage as independent charges.

## Data that must not become disposable cache

`ToolResultStore` saves full payloads and metadata with paginated reads. Ordinary sessions do not opt into legacy capacity-eviction budgets. Do not purge historical tool artifacts under a TTL/LRU optimization: conversation references depend on them.

`MCPToolCatalog` replaces server descriptors, removes disconnected/deleted entries and preserves stable ordering. It is a live registry. Keep MCP refresh/change notifications instead of adding a competing TTL that could resurrect removed tools.

No semantic cache is introduced for model answers or tool side effects. Such reuse needs a separate correctness policy for freshness, identity, authorization and mutation semantics.

## Validation and release gates

Tests use actual production sources and original dependencies:

- Eleven search lifecycle cases: TTL/rollback, completion-time freshness, LRU, oversized values, coalescing, individual/all cancellation, diagnostic isolation, invalidation and failures.
- Seven accounting cases: missing/partial values, subset totals, legacy Codable, coverage, invalid counts, weighted fractions and readable exports.
- Six OpenTelemetry cases: safe settings, real SDK export of usage, content exclusion, task-context isolation, streaming lifetime/idempotence and shutdown.
- Producer regressions separately drive real `streamText` span production. Bridge attribute tests do not replace producer validation.
- Integration verifies dependency/source graph generation and native app wiring/UI. A package proof is not an app archive or distribution claim.

Reuse successful unchanged-input proof. Re-run affected checks when production sources, dependencies, graph or compiler inputs change. Record integration SHA, dependency identities, toolchain, result and raw-log digest under `docs/ai-cache/evidence`.

Cancellation/accounting/serialization fixtures need no live model calls. Actual cache efficacy and billed savings require a production-like workload and provider usage/billing evidence. This implementation does not invent those measurements.

### Minimal native proof closure

For the six OpenTelemetry bridge cases, use a native Swift package harness with target name `HanlinChatCore`, the unmodified production `HanlinOpenTelemetryTracer.swift`, and test target containing unmodified `HanlinOpenTelemetryTracerTests.swift`. Dependencies must be original `SwiftAISDK` at the integration-pinned producer revision and original `OpenTelemetryApi`/`OpenTelemetrySdk` at 2.6.0. Foundation, OSLog and Synchronization come from the Apple toolchain. No fake implementation of those modules is acceptable. The test's capturing exporter is only a destination for original SDK spans/processors.

Run the suite filter `HanlinOpenTelemetryTracerTests` with bounded build jobs on the designated Mac. The full HanlinPlatform target is also valid if already prepared; this smaller proof closure avoids compiling unrelated application subsystems merely to establish adapter behavior.

For the eighteen local-cache/accounting cases, real source closure is `WebSearchTool.swift`; all seven `AutomaticSearch` Swift files except `AutomaticSearchMigration.swift`; `AgentTokenUsage.swift`; and the two new tests `AutomaticWebSearchCacheTests.swift` / `AgentTokenUsageCacheTests.swift`. Original LRUCache 1.3.0 is the package dependency. The conditional `HanlinCacheProof` test import supports this exact-production-source harness.
