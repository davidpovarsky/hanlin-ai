# Hanlin Expo Searchable blank-content regression

Date: 2026-10-29

Affected host: TestFlight Build 86201, native Expo branch commit 0504bd66.
Failing miniapps: Modular Text Search 1.1.0 and 1.1.1.
Working fallback: Modular Text Search 1.1.2 at 46f36ff3.
Host bridge candidate fix: 050bceb4 in fix/expo-searchable-content-bridge-20261029.

## Observed evidence

The physical iPad successfully rendered Sefaria results through native URLSession when the root native SwiftUI List was direct (1.1.2). With the Hanlin custom Searchable around the identical List (1.1.0 and 1.1.1), the native search field and title appeared, but the wrapped List content disappeared, including Search and Connection Test native buttons. This indicates a search-content composition issue in Hanlin Expo UI, rather than Sefaria networking.

The custom Searchable is defined in Packages/HanlinExpoUI/src/manual-components.tsx and implemented in Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoUIModule.swift. It is a Hanlin custom Expo bridge, not a built-in component of the pinned @expo/ui package.

## Failure mechanism hypothesis

The original React Searchable wrapped children inside a HanlinSlotView named content. The Swift side extracted that slot and applied SwiftUI .searchable to the slot view, rather than directly to the native List. Thus the navigation-bar search UI could render while the intermediate view failed to expose its native child List.

The candidate fix sends direct children to the native Searchable, renders the native child List directly in SwiftUI, provides a compatibility path that flattens children from legacy named-content slots, and avoids attaching an empty searchSuggestions modifier when there are no suggestions.

Source inspection and the device A/B observations strongly indicate the wrapper boundary is at fault. The specific native failure is not conclusively established until simulator and physical-device verification.

## Real regression test

The ExpoSwiftUIProbe fixture contains a minimal Searchable with a native List and marker SEARCHABLE_CONTENT_VISIBLE. The new test HanlinExpoProductionE2ETests/testProductionExpoSearchableContentAndEvents checks, in order:

1. The wrapped List marker exists in the native accessibility hierarchy.
2. A button inside the wrapped List responds and updates React state.
3. Typing in the native search field updates React state.
4. Pressing the native Search keyboard action delivers an onSubmit event.

The validate-expo-runtime-spike.yml workflow now builds this fixture with pinned Expo tooling and runs the test on an iOS simulator.

## Release gating

Do not change or remove the working 1.1.2 install on Build 86201.
The native bridge fix needs a newly compiled Host/TestFlight build; merely installing a new hanlinExpo archive cannot replace Swift framework code.
A new Modular Text Search 1.2.0 source package, using native Searchable and the unchanged URLSession transport, is prepared on the fix branch; do not install it on the old Host.
Before closure: pass simulator native E2E, preserve existing Expo/NativeScript regression tests, and verify the actual native search field, results, full text, and relaunch on a physical iPad.
