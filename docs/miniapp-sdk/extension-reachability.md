# NativeScript / Expo extension reachability

Status: **IN_PROGRESS — source audit only**.

Base commit: `604412848f81f96a32d68c84ddfc35f174df4cb6`. Exact current file hashes and line anchors are in [the JSON matrix](extension-reachability.json).
Runtime/API/version authority is [source-inventory.json](source-inventory.json); this matrix consumes it rather than maintaining a second SDK contract.

The four actual extension targets × two engines × five canonical runtimes form40 cells. Live Activity, Host AppIntent, Shortcuts and foreground add40 more.
A declared bridge, rendered snapshot, queued command or widget-local callback is not a complete ingress → executor → returned receipt proof. No signed physical or per-surface E2E pass is inferred.

| Surface | Engine | Node | TS | Python | JSC | Shell |
|---|---|---|---|---|---|---|
| share | hanlinNativeScript | disconnected | disconnected | disconnected | disconnected | disconnected |
| share | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| translation | hanlinNativeScript | disconnected | disconnected | disconnected | disconnected | disconnected |
| translation | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| widget | hanlinNativeScript | disconnected | disconnected | disconnected | disconnected | disconnected |
| widget | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| notification | hanlinNativeScript | disconnected | disconnected | disconnected | disconnected | disconnected |
| notification | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| liveActivity | hanlinNativeScript | disconnected | disconnected | disconnected | disconnected | disconnected |
| liveActivity | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| hostAppIntent | hanlinNativeScript | partially-wired | disconnected | partially-wired | partially-wired | disconnected |
| hostAppIntent | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| shortcuts | hanlinNativeScript | partially-wired | disconnected | partially-wired | partially-wired | disconnected |
| shortcuts | hanlinExpo | disconnected | disconnected | disconnected | disconnected | disconnected |
| foreground | hanlinNativeScript | partially-wired | disconnected | partially-wired | partially-wired | disconnected |
| foreground | hanlinExpo | not-tested | not-tested | not-tested | not-tested | not-tested |

## Existing path boundaries

- **share** (ChavrusaChatShare): share-inbox.json has no Host consumer; only borrowed provider URLs are persisted, not an owned attachment transaction. Follow-up: INT-04. Sources: [shareWrite](../../ChavrusaChatShare/ShareViewController.swift#L55), [shareReadOnlyDeclaration](../../AI_HLY/Downstream/SystemIntegrations/ChavrusaShareInbox.swift#L17).
- **translation** (ChavrusaChatTranslationProvider): Declarative snapshot/action continuation is not an NS/Expo runtime route. Resume requires an appIntent entrypoint; Expo non-widget exposure is rejected. Follow-up: INT-02/INT-03. Sources: [translationSnapshot](../../ChavrusaChatTranslationProvider/TranslationProviderMiniAppView.swift#L41), [extensionIntent](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift#L51), [extensionQueue](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationQueue.swift#L13), [resume](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L1409), [expoExposureRejection](../../Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift#L443).
- **widget** (HanlinScriptingWidgets): Existing Expo/ScriptWidget callbacks commit revision/nonces in the widget-specific runtime. They do not expose the five canonical Host runtimes or an NS foreground VM. Follow-up: INT-02/INT-03. Sources: [widgetBundle](../../HanlinScriptingWidgets/HanlinScriptingWidgets.swift#L11), [widgetIntent](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinGenericWidgetActionIntent.swift#L14), [widgetCallback](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetActionExecutor.swift#L45).
- **notification** (ChavrusaChatNotificationService): Media attachment/category delivery only; no authenticated package event envelope, Host consumer or MiniApp receipt. Follow-up: INT-05. Sources: [notification](../../ChavrusaChatNotificationService/NotificationService.swift#L9).
- **liveActivity** (HanlinScriptingWidgets): Static ActivityKit presentation is not a canonical Node/TS/Python/JSC/Shell execution path. Follow-up: INT-02/INT-03. Sources: [widgetBundle](../../HanlinScriptingWidgets/HanlinScriptingWidgets.swift#L11), [extensionIntent](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift#L51), [extensionQueue](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationQueue.swift#L13).
- **hostAppIntent** (AI_Hanlin / HanlinScriptExtensions): NS declared action can dispatch through the existing broker and persist its action value/status in a protected durable receipt. Busy NS session yields needsForeground; Expo yields an explicit unsupported receipt. Generic runtime callbacks, readback to system ingress and presentation-context propagation remain incomplete; native delivery tests pending. Follow-up: INT-02/INT-03. Sources: [extensionIntent](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptAppIntentBridge.swift#L51), [extensionQueue](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationQueue.swift#L13), [extensionReceipts](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationDelivery.swift#L36), [extensionExecutor](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationExecutor.swift#L14), [resume](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L1409), [requestBroker](../../Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinMiniAppRequestBroker.swift#L143), [headless](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L709), [nativeSession](../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift#L84), [expoIntentRejection](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L1480).
- **shortcuts** (HanlinScriptingWidgets / AI_Hanlin): Generic MiniApp action enqueues foreground continuation. Registered Siri phrases are alarm/notification operations; not an all-runtime MiniApp API. Follow-up: INT-02/INT-03. Sources: [shortcutIntent](../../HanlinScriptingWidgets/HanlinScriptingAppIntents.swift#L58), [hostShortcuts](../../AI_HLY/Downstream/SystemIntegrations/ChavrusaSystemIntegrations.swift#L92), [extensionQueue](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationQueue.swift#L13), [extensionReceipts](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationDelivery.swift#L36), [extensionExecutor](../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinInvocationExecutor.swift#L14), [resume](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L1409), [headless](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L709), [expoIntentRejection](../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift#L1480).
- **foreground** (AI_Hanlin): Source-wired Host calls still require real JS->native->executor->receipt tests; legacy NS strings lose stderr/status/artifacts and generic TS/Shell are absent. Follow-up: INT-03/INT-06/SDK-03/SDK-04. Sources: [nativeBridge](../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include/HanlinNativeServicesBridge.h#L9), [nativeAdapter](../../AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift#L95), [nativeSession](../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift#L84), [expoFacade](../../Packages/HanlinExpoUI/src/host-services.ts#L35), [expoModule](../../Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinHostServicesModule.swift#L27), [expoAdapter](../../AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift#L63), [runtimeBroker](../../AI_HLY/Downstream/HostServices/Runtime/HanlinRuntimeBroker.swift#L18), [callerContext](../../AI_HLY/Downstream/HostServices/Core/HanlinHostCallContext.swift#L12).

## Identity, permissions and proof

- App Group/other entitlements in JSON are source declarations. Exported signed entitlement/profile identity is NOT_VERIFIED here.
- TestFlight93401 is the historical owner delivery at7fa8fe26. It does not prove this branch, current framework identity, or this matrix. No IPA is generated by this audit.
- NS Node/Python/JSC legacy callbacks are string/error callbacks. Generic TS/Shell and full structured results are missing. One global active NS session requires real arbitration, not a second unowned VM.
- Expo's existing TypeScript facade validates all5 canonical kinds through invoke(runtime.execute). Its native legacy executeRuntime now rejects unknown kinds and propagates failure/cancellation; actual five-backend regressions and complete JS receipt coverage remain pending under INT-06.
- The17 SystemServicesBroker declarations are inventoried separately. They do not prove a public NS/Expo binding, actual OS permission, UI presentation context or device availability. Direct native metadata calls are a separate path.
- ControlWidget/CoreSpotlight names occur in exposure contracts; the source scan does not find an implemented corresponding target/index. They are not added as executable surfaces.
- The existing ResumeQueue now carries delivery metadata, leases, duplicate/TTL/cancel handling and protected durable Receipts. Its host dispatcher retains actual action values; this is not yet a complete generic runtime/attachment/system-ingress result contract. Native queue/executor tests are pending. No new engine or automatic Host Node/Python/Shell launch inside an extension.

## Verification

Run the SDK source audit first, then `py -3 Scripts/Audit/audit_miniapp_reachability.py --check`. Both fail on source drift; runtime execution is not part of this audit.
INT-02/03/04/05/06/07 and SDK-02…08 remain open. This is the prerequisite map, not their implementation or final acceptance.
