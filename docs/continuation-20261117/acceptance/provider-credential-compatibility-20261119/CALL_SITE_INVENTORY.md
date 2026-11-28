# Original provider credential call-site inventory

Source inputs are captured in base-manifest.json; only code was inspected, never live model records or credential values.

| Owner / route | Original files and relevant entry points | Proposal handling |
|---|---|---|
| Persistent schema | Model/APIKeys.swift, SearchKeys.swift, ToolKeys.swift; AppDataManager in AI_HLY.swift | All model/container/schema/entitlement inputs unchanged. Existing String representation remains active for legacy users. |
| Existing API editor | Views/Components/APISettingView.swift: EditKeyContent | Transient draft, explicit compatible commit, current-value checks, safe failure display, current selected compact configuration refresh with a separate publication-only retry. |
| New custom provider | Same file: AddCustomProviderForm.saveCustomProvider | Original form already had transient state; compatible insert now verifies original durable row and rolls back failed insertion. Secure activation is separate. |
| Search, map, weather editors | Same file: SearchSettingView, MapSettingView, WeatherSettingView | Transient drafts and compatible commit. Parent drafts reset on dismissal. Built-in keyless/AppleMap sentinel behavior remains available. |
| Typed SDK credentials and request construction | Services/ChatServices/APIManager.swift: credential, current-provider check after await, getAPIKey | Injected original host resolver, exact-byte current credential check, original namespace/request/model/epoch guards preserved. |
| Tool credentials | APIManager.findUseMap/findUseWeather/getActiveSearchEngine | Current original selected record resolved before use; stored handles never used as credentials. |
| Vision / TTS / optimization | VisionServices/VisionAPI.swift; ChatServices/TextToSpeech.swift; SystemOptimizer.swift | Resolved original current APIKeys value. |
| Discovery / capability probes | APIServices/ModelRefreshService.swift | Explicit transient settings configuration takes precedence for actual discovery/probe requests, including empty values; absent override resolves the saved owner. No draft persistence. |
| Scripting model requests | HanlinScriptingAssistantProviderAdapter.resolveConfiguration | Resolved original selected APIKeys value; no generic package access to app model schema. |
| Compact publisher | HanlinScriptingPlatformAIIntegration.publishCompactAgentConfig | Legacy raw config preserved until explicit secured adoption; secured rows publish only a reference. Existing file-store location injectable for actual native test. |
| Compact reader | HanlinCompactAgentContracts; TranslationProviderSession | Optional reference in backward-readable JSON; explicit host resolver; no stale loaded-config cache. Legacy API never exposes an opaque handle as a raw secret. |
| Chat model availability | HanlinDefaultChatPolicy, ModelsView, SettingsView, SettingsViewComponents | Resolved availability; original selection metadata retained where availability is uncertain. |
| Quick tools / embedding / canvas | QuickToolsView, KnowledgeWritingView, ChatViewComponents, ModelManagementView | Throwing resolution at request construction; no empty fallback for an unreadable handle. Legacy nil/default behavior retained. |
| Automatic search bootstrap | AutomaticSearchMigration.reconcileDefaultProvider | Preserve manual selection when a handle is unavailable; no credential mutation/migration. |
| Catalog bootstrap / duplicate preservation | Services/DataServices/PreLoad.swift | Intentionally unchanged raw stored-value comparisons; do not resolve/re-persist plaintext or delete Keychain generations during duplicate/catalog reconciliation. |
| Catalog initial values | InfoServices.getKeyList/getSearchKeyList/getToolKeyList | 40 empty literals, LOCAL sentinel and APPLEMAP sentinel; no user credential read. Metadata-only classification retained in catalog-credential-metadata.json. |
| Native acceptance providers | AgentRuntimeUIAcceptanceProvider and HanlinNativeA2UIAcceptanceProvider | Unchanged original fixture creation. No automatic staging or synchronization of CI-supplied secrets. |
| Existing Runtime/MCP secret owners | RuntimeEnvironmentSecretStore, MCPSecretStore | Unchanged separate services/policies. Their device-only setting is not copied into provider policy. |

Remaining raw field operations in the inspected proposal tree are the unchanged original three model initializers and the compact publisher reading the stored representation. The host owner uses storedCredential as an explicit alias to the unchanged field. Unchanged PreLoad compares stored representations for preservation. Dictionary key uses elsewhere are unrelated.

No direct original UI binding assigns typed text into a persistent .key field after this proposal. Production draft Save/insert remains compatible; only the separate DO-NOT-APPLY overlay selects secured writes for legacy rows/new providers.
