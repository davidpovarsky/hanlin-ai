# Original ExpoAsset native integration

The three original Expo acceptance cases reached the real React/Hermes host, then target stdout recorded `Cannot find native module 'ExpoAsset'` before their JavaScript roots rendered. The root's bounded original stdout extract is referenced by exact hash in the receipt. Actual `SET_RUNTIME_DONE` observations ruled out the earlier scheduler hypothesis.

The original SDK7 bytes explain the startup dependency: `expo/src/launch/registerRootComponent.tsx` imports `Expo.fx`, which eagerly imports `expo-asset`. Original `expo-asset/src/ExpoAsset.ts` calls `requireNativeModule('ExpoAsset')`. The previous Hanlin module provider, package manifest, native dependency lock and native artifact catalog omitted that real module.

## Original implementation and graph

The installed publication is `expo-asset@58.0.21`, already required by original `expo@58.0.26` through its `~58.0.21` range. Its original `ios/AssetModule.swift` is retained unchanged as evidence with original CocoaPods and SwiftPM metadata. It defines the actual `ExpoAsset` module and complete `downloadAsync` implementation. This publication contains Swift source rather than a prebuilt Apple XCFramework.

The existing original Expo/CocoaPods producer project already exposes the `ExpoAsset` scheme and pins its only native pod dependency, `ExpoModulesCore`. Original cached tarball SHA-512 matches the npm lock; the owner's read-only cache observation supplies the exact SHA-256 used in the candidate lock. The observation listed the same cache file twice because two candidate roots resolved identically; there is one artifact.

Original Core initializes `AppContext.fileSystem` with its own `FileSystemManager`. The retained source observation resolves that optional dependency question without adding another native module.

## Source changes

- Add the original ExpoAsset framework to the runtime package and native artifact catalog. The candidate catalog requires fifteen targets and removes none.
- Register `ExpoAsset.AssetModule` with `name: nil`, matching the original autolinker's interpretation of its string module configuration. Its own `Name("ExpoAsset")` stays authoritative.
- Extend the existing original CocoaPods producer to build selected `original-cocoapods` schemes using the same device/simulator commands and original podspecs. Every output retains its own publication and source-build receipt. Selected version, integrity and URL must match the current npm lock.
- Follow Expo's own expo-asset version range in the existing updater, preserving source-only and published-prebuilt layouts. Extend the existing coherent-version regression for this dependency.

No Expo implementation or API is replaced. Copied original native source is evidence only; application binaries will be built from the installed original publication by the existing producer.

## Integration and verification boundary

This prepares source and provenance, without claiming a native build or runtime pass. The original unified manifest generator must refresh root `Package.swift` and its receipt before the complete source closure is published. Native owner retains generation, compilation, preparation/export, Host/SDK preparation and consumer execution.

Changed native preparation inputs invalidate the former native catalog identity. The SDK consumes the native lock directly and generated source inventories indirectly, so SDK7 archive identity cannot stand for the corrected build. Capture and reconcile the new Host ZIP, SDK manifest, documentation results, native catalog and actual embedded copies after preparation.

The three original failed Expo cases remain failed until corrected execution proves their original widget, worklet, UIKit and interaction assertions. Source review and framework compilation cannot substitute for behavioral results.

All eight production/regression paths, before/after hashes and modes are listed in `source-changes.json`. Raw observations retain their historical source. `Podfile.lock.gz` decompresses to the exact original Podfile.lock hash recorded in the receipt.
