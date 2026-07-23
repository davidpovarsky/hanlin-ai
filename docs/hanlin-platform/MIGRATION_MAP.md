# Migration map

## Preserve as separate concerns

| Existing area | Preserved responsibility |
| --- | --- |
| `Downstream/RuntimeCore` | execution engines, workspaces, package mechanics, lifecycle, runtime diagnostics |
| `Downstream/MCP` | MCP protocol, transports, servers, sessions, resources/prompts/tools, installer and UI |
| `NativeUIBlock` / renderer | compact native tool-result representation inside chat |
| `Downstream/AgentActivity` | activity, evidence, transcript, and provider-neutral result presentation |

## Adapt incrementally

| Existing type/system | Target adapter or role |
| --- | --- |
| `NativeAppManifest` | adapter to `HanlinAppDescriptor` |
| `NativeAppModule` | `LegacyNativeAppModuleAdapter`, then gradual `HanlinNativeModule` adoption |
| `NativeAppRegistry` | provider feeding `HanlinAppCatalog` |
| `NativeAppPlatformServices` | app adapter to canonical service protocols |
| `NativeCapabilityRegistry` | migration facade over the Phase 2 permission broker |
| `NativeAppActionBus` | adapter to `HanlinActionDispatcher` |
| `NativeTool` | adapter to typed `HanlinTool` |
| `NativeToolCatalog` | provider feeding one typed tool registry |
| MCP tools | provider adapter into the same tool registry and policy |
| `TypeScriptRuntimeService` | compiler adapter, never persistent app runtime |
| `JavaScriptCoreRuntimeService` | preserve one-shot developer execution; add separate sandboxed sessions |
| `NativeAppLaunchRequest` | adapter into one native/script/hybrid launch request |

## Ordered migration

1. Establish pure contracts and value/version types in a new package.
2. Add capability, permission, policy, and audit services behind protocols.
3. Adapt one native built-in application end-to-end before migrating others.
4. Route current native apps and current native/MCP tools through unified
   catalogs while preserving presentation and selection.
5. Add script package storage and approval without execution.
6. Add compiler/language-service use of the exact Scripting baseline.
7. Add persistent JavaScriptCore sessions and the versioned bridge.
8. Add the reconciler and a separate ScriptUI renderer.
9. Add platform services, chat/tool integration, advanced APIs, and extensions
   only through their gates.

## Expected upstream-file touchpoints

Phase 0 minimally modifies `.gitignore` to unignore the two authorized,
hash-verified Scripting `tsconfig.json` files that the existing broad
`*config.json` rule would otherwise omit. It also adds a narrow
`.gitattributes` rule that disables text normalization only within the
byte-preserved compatibility baseline. Later unavoidable touchpoints are:

| Path/area | Narrow reason |
| --- | --- |
| `AI_HLY/AI_HLY.swift` | platform bootstrap and unified launch scene |
| `AI_HLY/MainTabView.swift` | route Apps Hub/settings through unified platform UI |
| selected Apps Hub/settings views | catalog and permission/package center entry points |
| narrow chat integration | launch/return actions and unified tool adapter |
| `AI_HLY.xcodeproj/project.pbxproj` | one local package reference and later target/resource wiring |
| `.github/workflows/build-ios26-unsigned-ipa.yml` | manual-only Phase 1 validation mode on the already registered macOS/Xcode workflow |
| Info.plist/localization | only real service purpose strings and user-facing text |
| entitlements | only in the extension/service phase that requires them |
| runtime preparation scripts | deterministic Script SDK resource packaging |

Every touchpoint must remain localized, avoid unrelated formatting, and name
the downstream component it connects.

## Upstream merge policy

The checkout is treated as CherryHQ-derived, but no upstream remote is
configured. New platform logic stays in `Packages/HanlinPlatform`,
`AI_HLY/Downstream/HanlinIntegration`, `Reference/ScriptingCompatibility`,
`Scripts/ScriptingReference`, and `docs/hanlin-platform`. Existing upstream
files receive bridges only. A future upstream update must compare substantive
changes and preserve downstream behavior through adapters; it must not choose
ours/theirs wholesale.
