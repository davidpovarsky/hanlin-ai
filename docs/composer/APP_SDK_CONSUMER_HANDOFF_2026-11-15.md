# Composer app/SDK consumer handoff — 2026-11-15

The editor correction is integrated in `e9c07cbd8a77e990ea88a667556fa2574f83eebb`. Its original one-plus-four native executions remain separate authenticated evidence; this work does not change their ten compiled source/test files or rerun those cases.

## Available source and missing app graph

SDK branch commit `3885b01c830573f75ee69715925d0f4e950422e4` contains the actual `AI_HLY/Model/HanlinAppleModelCatalogAdapter.swift`, introduced in `3cfc780dbaa09a463684b24d3eb6116f35ddb41e`. It owns the canonical UUID, idempotent append-only registration and availability-checked configuration. The real provider is `Packages/HanlinAgentSDK/Sources/HanlinAgentCore/Providers/HanlinAppleOnDeviceProvider.swift`. Composer consumes these identities without another registrar, model store, selector or fallback.

At integration commit `e9c07cbd`, the adapter file is absent and the committed app project has no `HanlinAgentCore`, `HanlinAgentSDK` or adapter entry. The SDK branch's committed app project also has no such entries. Package source availability therefore does not yet establish an SDK-linked app consumer. No sibling dirty edits were imported or changed. Target/project ownership remains with the existing integration/SDK lanes.

The earlier full-app failure43650510166 remains an unresolved Expo-header gate. The later imported Runtime host canonical-generation correction changes Node Host files, not that header staging. An identical full-app attempt on Composer's unchanged app-build inputs was not dispatched. These observations are blockers to actual app execution, not native test failures.

## Existing picker and expanded cards

Composer's source-only tranche remains in these exact paths:

- `AI_HLY/Downstream/ChatInput/HanlinModelPickerPopover.swift`: existing picker imports the real SDK when linked, uses the adapter UUID, refreshes actual availability on entry/foreground and rechecks on tap. Original array indices are forwarded unchanged. The same compact-row projection now has an internal static entry point consumed by the view and tests; no second implementation was added.
- `AI_HLY/Downstream/ChatInput/HanlinComposerPopupView.swift` and `AI_HLY/Views/Components/ChatViewBottom.swift`: expanded Tools/Skills/MCP/Runtime cards consume the existing live capability projection, with enabled styling/checkmarks/accessibility values and no duplicate external chip row.
- `AI_HLYTests/HanlinOrganizerDockParityTests.swift` and `AI_HLYUITests/HanlinMorphComposerUITests.swift`: actual app consumer tests, not inputs to the isolated editor test target.

The new real-catalog consumer case creates an in-memory SwiftData store using the actual `AllModels`, calls the actual adapter twice, then projects the resulting catalog through the existing picker. It checks canonical provider identity, append-only order, retained hidden slots, selected indices and the actual provider availability. When the test target cannot import the SDK it records a failure explicitly; missing linkage is not a skipped/pass branch. The compact case covers a native row beyond the first four, current cloud/native selections, unavailable/hidden native rows and duplicate native identity.

## Required execution and evidence

After the authoritative app/SDK graph and header fix are available, compile the real app and run these exact new/affected methods with retained xcresult/case/device provenance:

1. `AI_HLYTests/ModelPopoverZoomOrderTests/nativeCatalogRegistrationFeedsExistingPickerWithoutIndexDrift()`
2. `AI_HLYTests/ModelPopoverZoomOrderTests/nativeVisibilityKeepsOriginalIndices()`
3. `AI_HLYTests/ModelPopoverZoomOrderTests/compactNativeVisibilityKeepsFeaturedAndSelectedIndices()`
4. `AI_HLYTests/ComposerActionsParityTests/detachedCapabilitiesProjectRealModeState()`
5. `AI_HLYTests/ChatComposerSessionBridgeTests/toolUseBindingRemainsScopedToItsChat()`
6. `AI_HLYUITests/HanlinMorphComposerUITests/testEnabledToolsChipOpensSettingsAndContextMenuDisables`

These are the actual app target/scheme bundle names, verified against `project.pbxproj`, `AI_HLY.xcscheme` and the exact-selector router. The isolated editor diagnostic's synthetic bundle name `AI_HanlinTests` must not be used for this app route.

These selectors are **NOT_RUN**. Local Windows Swift frontend parsing and whitespace checks passed only for the changed picker/parity source. No SDK typecheck, app compile, native generation, selection/send, UI/visual or physical-device result is claimed. The separate editor5 passes do not cover this tranche. No broad CI or native-editor rerun is justified by these changes.

## Scoped routing repair and actual portable result

`Scripts/CI/affected-validation-map.json` lacked an entry for the actual `AI_HLYUITests/HanlinMorphComposerUITests.swift` file. It now maps that exact path to its existing suite and targeted simulator UI group. No workflow/trigger, global fallback or unrelated component mapping changes. A regression in the existing `Scripts/CI/Tests/test_affected_validation.py` checks both ordinary file routing and bounded mixed unit/UI selectors, excluding device/IPA builds.

The portable planner suite executed96 cases: **95 PASS / 1 FAILED**, including PASS for the new Composer routing regression. The failure is the existing `test_runtime_tooling_full_acceptance_deduplication_and_scoped_build`: it expects only `AgentSkillsExposureTests`, while the existing map also selects `HanlinCapabilityObservationTests`. The unchanged failing test was reexecuted with the original committed97fe29a0 map and failed identically. That expectation was preserved; no full-suite pass is claimed. Raw ignored logs: `build/evidence/composer-consumer-routing-tests.log` and `build/evidence/composer-routing-baseline-97fe29a0.log`.

A dry plan using exactly the five Composer product/test transplant paths and the six selectors above passed: five unit selectors, one UI selector, no broad/full/device/IPA/Runtime bundle execution. Receipt `build/evidence/composer-consumer-net-dry-plan.json` is planning evidence only, zero Apple cases executed. Comparing the two entire diverged branches initially surfaced unrelated unmapped SDK/Split/A2UI paths; those paths were not imported, mapped or used to broaden this scope. Integration should plan the actual net transplant, not synchronize whole branches.

`protectedFilesAndReferenceMetadataRemainIntact()` is preserved verbatim. Authorized SDK/A2UI changes to its protected whole-file inputs still require the precise versioned integration contract amendment and protected-behavior proof already agreed with the manager. Do not replace hashes silently or omit that obligation. Compact/wide/RTL, keyboard/accessibility/Reduce Motion and authentic physical iPad/reference parity remain open. Both Asana tasks remain incomplete.
