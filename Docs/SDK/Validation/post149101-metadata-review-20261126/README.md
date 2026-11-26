# POST-149101 automatic metadata review corrections

Base integration: 827f764badba1ce51fbedba95ad597b52a44a22d.
Owner: root coordinates one Apple native validation and TestFlight release.

## Corrected behavior

1. Conversation metadata uses the existing HanlinAISDKAgentEngine provider pipeline for network models. Anthropic, Gemini, OpenAI Chat, compatible providers and Responses retain their original wire adapters. The native Apple engine is injected using HanlinAppleModelCatalogAdapter and HanlinAppleOnDeviceProvider. LOCAL uses the existing LocalLLMStreamDriver and LocalLLMStreamingAdapter; no remote key is required and local inference failure does not send its input to a remote provider.
2. A configured text optimizer is used when its model, provider and credentials are usable. Only pre-request configuration failures select the actual chat request model. The UI and headless controller pass that original model UUID. Provider or decoder failure does not retry another provider.
3. One metadata response contains both title and icon. It has no tools, one engine step, a 12,000-character input bound, a 2,048-token output setting, a 4,096-byte accepted-output bound and a 30-second cancellation deadline. Remote transport also has a 30-second timeout. Existing SDK transport error retry policy is reused; there is no additional metadata retry loop or icon request.
4. UI and headless metadata are scheduled after successful primary response completion and lease release. The response does not await metadata. This prevents loading a second LOCAL model while the initial response is still generating.
5. Jobs are keyed by ModelContainer identity and conversation UUID. Every job has a token, so an invalidated old job cannot release a newer job in its defer. Explicit rename (including the same placeholder), appearance changes, clear and delete invalidate outstanding results. Source user-row IDs/content and a fresh durable metadata snapshot are checked before apply.
6. The shared provider factory recognizes saved OpenAI-Response, plural openai-responses, historical openAIResponse, and openai-chatgpt-plan as Responses, including custom provider names/hosts. The old routing-characterization test now asserts the corrected contract.

## Validation classification

Executed here: Swift 6.4.3 Linux frontend syntax parsing of all nine changed/new Swift files; git diff --check. Receipt and exact source fingerprints are in syntax-validation.json. Syntax parsing is not type checking or a native build.

The original pure metadata decoder and its five existing tests are unchanged. The decoder SHA-256 is recorded for root to reuse its existing execution evidence without rerunning unchanged tests.

Required Apple validation, not executed by this child:

- AI_HanlinTests/HanlinConversationMetadataTests (16 tests: seven existing plus nine new persistence/concurrency/configuration regressions).
- HanlinChatCoreTests/GeneratedConversationMetadataProviderTests (five intercepted real provider protocols plus three stream completion/cancellation/bounds tests).
- HanlinChatCoreTests/ProviderRoutingTests, especially the parameterized Responses alias/host matrix.
- Native app build/type checking; existing old-store upgrade check for the new metadataWasManuallyEdited = false field.

The LOCAL test validates configuration/file routing with an injected generation boundary. It does not run a GGUF model. The network tests intercept provider HTTP and do not claim live model quality. Live Apple Foundation Models availability and actual GGUF inference depend on the owner device and installed models. This change does not claim that the schema upgrade has passed; root must record its actual native result.

## Tests added

Clear-history delayed completion; explicit same-placeholder rename; dedup across separate ModelContexts; manual edits from a separate ModelContext; requested model UUID overriding saved selection; valid preferred optimizer vs missing credentials and no post-request provider fallback; local file routing without API keys; edited source rejection; deterministic invalidated-old-job/new-job token race.

Provider tests assert the native request path/body and one successful request for OpenAI, compatible, Anthropic, Gemini and Responses. Stream tests reject missing completion, truncation, oversized UTF-8 output and cancellation while excluding reasoning from JSON.
