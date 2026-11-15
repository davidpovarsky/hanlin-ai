# App model mapping

`HanlinAppleModelCatalogAdapter` in `AI_HLY/Model` owns the single native AllModels row:
UUID `76298A03-2251-4D79-8E19-5E29309C5DA1`, modelID `apple-system-on-device`, company `APPLE`.
Registration is idempotent and appends at max existing position + 1. It never deletes/reorders existing
rows or rewrites `ChatRecords.useModel`. A conflicting reserved name or duplicate identity fails explicitly.
The existing startup preload protects that native row from its generic name deduplication and registers it
after ordinary catalog synchronization. The row is retained when the native model becomes unavailable.

Composer consumes the SAME original `modelTemp` array index for this UUID. Offer that row exactly once
only when `HanlinAppleOnDeviceProvider.availability == .available` (`import HanlinAgentCore`).
Do not add a detached model list or AllModels insertion in the picker. Its existing visibility predicates
must exclude this native row when unavailable. The row's normal isHidden value is false; the canonical
default-model policy explicitly excludes its UUID so it is selected manually. Availability loss retains
the chosen identity and fails generation rather than changing the selected index/provider.

`APIManager.processMessages` resolves the reserved native name only when exactly one matching row
has the canonical UUID. The generation branch validates that row and actual native availability BEFORE
the normal network/API-key configuration path. `processSDKAgentEngine` uses
`HanlinAppleOnDeviceProvider.makeEngine(configuration:)` for that row, with no network fetch and no
tool adapter. It uses the SAME canonical agent engine/event projection. Availability is checked again
when the engine and native generation start. Advertised capabilities remain text only.

`HanlinDefaultChatPolicy` and the startup preload are app code. App Split/manager must link the
`HanlinAgentCore` product from the existing nested SDK package into every target compiling these files;
no project.pbxproj changes were made here. This is a concrete package graph handoff, not optional imports.

Focused validation uses actual AllModels + ProviderModelCatalogMetadata + app adapter + default policy
sources, copied byte-for-byte into the existing style of isolated Apple package proof. Three SwiftData
cases exercise identity/idempotence/order/default exclusion, reserved-name preservation and current
availability/configuration. iOS compilation checks those exact sources. This harness does not compile
the entire APIManager/startup app or prove actual UI/physical model generation. Those gates remain OPEN.

The preceding SDK/Core proof ran at f26fe05fad224d30023b043165904ec89e3757e8:
run43722554901, job132837473769, 33 EXECUTED_PASS / 0 FAILED, iOS AgentCore compile PASS.
Later UUID channel/interaction source changes invalidate affected Session/structured-part obligations;
the next focused run executes them. Prior producer48 remains attributed to its original run, not replayed.
