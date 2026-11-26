# Task06: owned NativeScript Shortcuts admission

## Observed defect and exact base

Base: 3101be04fd745c829318c9efb5df50dc8ce57b10. The standalone Shortcuts entry creates a dedicated HanlinScriptingPlatform with presentation and foreground-drain ownership disabled. Its real executeShortcutCommand -> durable invocation executor -> dispatchResumeCommand -> canonical broker -> executeHeadlessAction path rejected every nonnil NativeScript process-global session, including the supported cooperating windowFactory owner. Consequently an otherwise supported Shortcut returned needsForeground and cancelled its unstarted queue record while a cooperating UI was open.

This was a production-path admission defect, not merely missing completion-helper tests.

## Bounded correction

Prepared handlers declaring hanlinNativeScript.windowFactory == 1 now enter HanlinNativeScriptWindowSession.open through the existing original shared VM. Each call owns a new immutable module namespace, provider, action registry, session storage and unattached native container. Its provider has canPresentUI=false. The existing action/capability/generation checks remain authoritative.

The platform reserves its own admission before suspension, refreshes the persisted registry after resolving files, then rechecks the actual process owner immediately before starting JavaScript. The final generation guard uses store.restore(): store.snapshots() only reads that store actor's cached registry and cannot observe another scene's or Shortcut's committed update. Only the existing cooperating owner can be shared. Legacy whole-application ownership still rejects another VM. A Shortcut that was not started is cancelled in the durable queue rather than replayed after its caller has already received failure.

Cancellation is checked before runtime admission and after the startup yield. Returning, throwing, cancelling or timing out closes only the action's owned window. The existing window registry invalidates its bridge/callbacks before the original VM can stop. Legacy headless teardown now unregisters its JS-owned provider before stopping that VM.

The small read-only activeRuntimeSessionIdentifier property distinguishes an existing cooperating owner from a legacy owner. No additional evaluator, engine or global provider selection was introduced.

## Canonical typed action registration

The existing native selector registerRequestHandler:capability:handler: was absent from the bound public Host Services facade. Cooperative entries therefore had no public way to register an action on their own provider. Commit 28b7a3d29c61377c97c8fbadf35375491c47528f adds:

~~~typescript
registerWindowFactory(({services}) => {
  services.registerRequestHandler("probe", "inter-app.share", async ({caller, parameters}) => {
    return {caller, parameters, completed: true};
  });
  return null;
});
~~~

The handler accepts canonical JSON and returns canonical JSON or a Promise. It registers synchronously, remains bound to that provider, and is removed through the existing native provider invalidation when the window closes. Source and packaged declarations are generated together by the original TypeScript generator. The neutral global provider is unchanged.

## Verification actually executed on Oracle

- Original TypeScript 5.9.3 strict facade generation: PASS, including the existing negative fixture diagnostics and positive/negative consumers of the actual packaged declaration entry.
- Scripts/NativeScript/host-service-actions.test.mjs: 3 tests PASS. These test the actual generated facade against controlled bridge boundary objects; they are not original native runtime acceptance.
- Scripts/Audit/Tests/expo-operation-contract.test.mjs: 4 tests PASS. The fourth proves the explicit Shortcuts progress route cannot be accepted after removing validation, changing the operation, enabling presentation or redirecting dispatch to the shared platform.
- Swift frontend parse of the changed platform, window session and actual native regression file: PASS. This is syntax evidence only.
- Node syntax check of the embedded original NativeScript fixture: PASS.
- git diff --check: PASS.

The audit correction is separately committed as 4ba7a1ac55f9b8da85ce95b75c6d60498089322c. It verifies actual source linkage instead of accepting an arbitrary delegated operation prefix.

## Required Apple native regression gate

Two XCTest methods in HanlinMiniAppsTests/NativeScriptShortcutConcurrencyTests.swift. Both are NOT_RUN at this handoff:

1. HanlinMiniAppsTests/NativeScriptShortcutConcurrencyTests/testOriginalWindowSurvivesReverseShortcutsCancellationDeadlineAndStaleGeneration
2. HanlinMiniAppsTests/NativeScriptShortcutConcurrencyTests/testLegacyOwnerRejectsBothFactoryAndLegacyShortcutsWithoutQueuedReplay

The first installs real prepared packages through HanlinAtomicScriptStore, attaches an actual foreground native controller to a UIWindow, and dispatches three independent commands through the production durable Shortcuts path. Two use the same package; one uses a different package. Original JS handlers report their window UUID, module path, process PID, state path, module counter and nonce through their own native service callback. The test releases actual file gates in reverse order and checks separate results, same-process ownership, unchanged foreground UI and independent equal-name state files.

It also tests duplicate command delivery without a new JS window, cancellation of an admitted handler, an actual durable deadline, late original JS completions after each closes, rejection of stale-generation/disabled commands before new JS starts, and continued foreground action execution. A separately preloaded platform and a second real store actor reproduce the stale-registry admission case directly at executeHeadlessAction after the other actor commits an update. These are assertions inside one native method, not separate completed tests.

The second opens an actual legacy NativeScript UI and verifies that both a cooperating and a legacy Shortcut are rejected without a second VM or abandoned replay.

Across the two methods the source requests ten Shortcut deliveries with nine distinct command IDs. The existing baseline test inventories remain separate and unchanged.

## Limits

Native compilation/execution is owned by the Mac build agent. No original NativeScript iOS runtime, UIKit test, system Shortcuts UI, physical device or cross-engine concurrency result is claimed here. These tests exercise the production Shortcuts dispatcher from the app test host; system App Intents/Shortcuts presentation remains a separate gate. iOS27.2 simulator runtime availability (24B8117) and Xcode/iPhoneOS build SDK27.0 are separate observed facts, not an execution receipt.

Supported NativeScript concurrency remains cooperative windowFactory entries in the original shared main VM. Arbitrary legacy applications are not separate VM isolates. Cancellation closes the owned native scope and rejects stale results/callbacks; it does not preempt an arbitrary synchronous JavaScript loop in the shared VM. The native regression deliberately exercises late asynchronous completion while the unrelated foreground owner remains alive.
