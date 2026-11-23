# Hanlin SDK: one original implementation, selectable products

The repository's root package is **HanlinSDK**. Its generated graph is derived from the original module manifests and source paths. Hanlin's own application and extension executables are thin owners of app identity, entitlements and OS entry points; the shared implementation lives in the SDK. The current complete graph exposes **43 products and 107 targets**, including **502 original application Swift source files** in the preserved `AI_Hanlin` module. The [generated inventory](../../docs/agent-sdk/unified-package-manifest.json) is the authoritative list.

## Choose what the host needs

| Integration | Public products | Starting point |
| --- | --- | --- |
| Full original Hanlin workspace, one conversation, panels, Vision, or the full original engine without mounting UI | `HanlinApplication` (import `AI_Hanlin`) | [Application embedding and original conversation owner](HanlinApplicationEmbedding.md) |
| Independently injected agent, host tools, permissions, navigation and persistence | `HanlinAgentCore`, `HanlinHostContracts`, `HanlinPersistenceAdapters`, `HanlinChatCore`, `HanlinPlatformContracts` | [Current host interfaces](../../Packages/HanlinAgentSDK/Sources/HanlinHostContracts), [current navigation integration](HanlinNavigationIntegration20261123.md) |
| Original Composer, native editor, bubbles, thinking/tool activity, sources and motion | `HanlinChatUI`, `HanlinAgentActivityCore`, `HanlinAgentActivityUI` | [Original activity composition](../../docs/agent-sdk/HANLIN_AGENT_ACTIVITY_SDK.md), [scoped presentation settings](HanlinHostPresentationCustomization.md) |
| Original rich rendering, OpenUI and A2UI | `HanlinPresentationKit`, `HanlinRichUI`, `HanlinA2UI` | [Presentation customization](HanlinHostPresentationCustomization.md); actual module interfaces in the selected profile |
| Shared localized strings, assets and typography | `HanlinLocalization` | Original bundles are selected and embedded with their owning targets; hosts do not copy the catalogs |
| Original Share, notification, translation and widget extensions | `HanlinExtensionContracts`, `HanlinShareExtensionUI`, `HanlinNotificationExtension`, `HanlinTranslationUI`, `HanlinWidgetUI` | [Extension integration and preserved type identities](HanlinExtensionSourceOwnership.md) |
| Scripting contracts, compiler, store, runtime and SwiftUI components | `HanlinMiniAppCore`, `HanlinScriptContracts`, `HanlinScriptCompiler`, `HanlinScriptStore`, `HanlinScriptRuntime`, `HanlinScriptingSDK`, `HanlinScriptUI` | Original module APIs; select the public products actually imported by the host |
| Scripting host services, device services, extension actions and application runtime | `HanlinScriptServices`, `HanlinScriptDeviceServices`, `HanlinScriptExtensions`, `HanlinScriptingApplicationRuntime` | [Extension host policy](HanlinExtensionSourceOwnership.md), [native asset contract](../../docs/agent-sdk/NATIVE_ARTIFACT_DISTRIBUTION.md) |
| NativeScript and Expo runtimes/components | `HanlinNativeScriptRuntime`, `HanlinExpoNativeAPI`, `HanlinExpoWidgetNative`, `HanlinExpoRuntime`, `HanlinExpoWidgetSubset` | [Native distribution and required host-stage commands](../../docs/agent-sdk/NATIVE_ARTIFACT_DISTRIBUTION.md) |
| Original MiniApps and content packages | `HanlinParityMiniApp`, `HanlinSefariaMiniApp`, `HanlinTextStudioMiniApp`, `HanlinWikipediaMiniApp`, `TorahLibraryKit` | Existing module APIs and original host integrations |
| Shared skill format, runtime support and product contracts | `HanlinSkillFormat`, `HanlinQuickJS` (module `CQuickJS`), `IOSSystemLite`, `HanlinProductSplit` | Original module manifests and interfaces |

MCP, Skills, provider configuration, search, knowledge, calendars and the other original Hanlin tools are available through the full application engine/context. Hosts that select only the independent agent product supply their actual tool and platform services through the public host contracts. Selecting a component never grants app permissions or silently installs a host's credentials.

## Install and update one canonical profile

Follow [SDK installation](../../docs/agent-sdk/SDK_INSTALLATION.md). The host locks a full immutable SDK commit and its chosen product list in `HanlinSDK.lock.json`. The shared installer materializes those products' original source/resource paths and derives the local package manifest. It does not create separate implementation copies. The host then links the one `Vendor/HanlinSDK` package.

For a compatible SDK update, change the locked revision and run that same installer. Shared engine, UI, design and resource changes come from the updated canonical source. Host code continues to own its app-specific tools, navigation destinations, account identity and credentials. Existing Gitlink-based hosts also commit their matching Gitlink; generated selection files remain managed outputs.

A source-only profile does not initialize or fetch unrelated native runtimes. A profile containing managed native targets requires the actual published URL/checksum catalog. The installer fails explicitly while that catalog is unpublished. The selected-profile installer remains required after publication because SwiftPM evaluates unused binary declarations in an unfiltered full graph.

The complete manifest declares Swift tools6.2, iOS27 and macOS26. The full original `HanlinApplication` uses UIKit and is an iOS/iPadOS product; declaring macOS for the aggregate does not make every target a macOS application. Use the relevant target's supported platform and actual native acceptance evidence.

## Place and configure original components

For the full conversation, retain one `HanlinApplicationContext` and use `HanlinConversationView`. To place the original input and transcript in separate areas, retain one `HanlinConversationPresentation`, then mount `HanlinConversationTranscriptView` and `HanlinConversationComposerView`. The host sets its own layout and the transcript obstruction inset. A Composer-only entry and original tool-activity view are also public. All call the existing conversation owner, stream projection, consent handling and persistence writer. See [the concrete API examples](HanlinApplicationEmbedding.md).

For smaller compositions, select the independent ChatUI, activity and rich-rendering products. The original components accept their existing data and callbacks. [Scoped modifiers](HanlinHostPresentationCustomization.md) configure colors, original activity/disclosure motion presets and Markdown rendering within a view subtree. Default values preserve the original design, animations and interactions; Reduce Motion remains authoritative. These APIs do not claim to replace every independent animation curve with one preset.

Provider/model management, conversation rename/pin/delete/history clearing and the headless stream use the same original implementation as Hanlin. See [conversation mutations and cancellation ownership](HanlinConversationMutations20261123.md). System integrations and extensions receive explicit host policy; see [notification, share and Vision ownership](HanlinSystemIntegrationOwnership20261123.md).

The full original native runtime has one active model container/profile per process. Reuse that context across views and windows. Independently injectable agent products are available when a host needs concurrent independent account engines. This preserves the original runtime authority instead of redirecting a running singleton to another account.

## Evidence and release boundaries

The source graph, portable checks, Apple compilation, native UI, real provider journeys, physical-device services and signed storage/cloud behavior are distinct evidence. The [dated requirement reconciliation](AcceptanceReconciliation20261123.md) records the original task scope and historical receipts; subsequent run and commit links in Asana identify newer results. [Motion acceptance](HanlinMotionAcceptance20261123.md) documents the original cases and the canonical SDK fixture.

The actual Hanlin, Lorvex, Maktabah/Otzaria and Anytype repositories use the same canonical installer and immutable SDK pin. Their native/visual results must identify the host commit, SDK commit, selected profile and applicable runtime. A profile installation or historical result is never presented as a current host acceptance pass.
