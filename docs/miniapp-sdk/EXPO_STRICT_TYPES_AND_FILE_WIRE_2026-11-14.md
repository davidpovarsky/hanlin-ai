# Strict Expo declarations and file wire

[נועם | DEV] [MAIN_SESSION]. SDK-04/07 and INT-06 remain IN_PROGRESS.

Both existing Expo templates now check their entire declaration closure under
strict TypeScript6.0.3 with skipLibCheck=false. The native-api config had been
ignored by the repository's broad *config.json rule; it is now explicitly tracked.
ES2022 uses the actual React Native globals instead of also loading browser DOM
globals. The virtualized-lists path selects the pinned package's current generated
export instead of its incompatible legacy index selected by the catch-all path.

Five exact declaration-file corrections preserve upstream attribution and reject
unknown original/source hashes. Three align RN0.88 generated declarations with
its actual Flow sources (nullable optional style, class-instance inference,
Document.textContent=null). Two align @nativescript/react-native9.1.2 with its
actual Host bridge: C constants take precedence over colliding global struct
constructors, while struct field types remain available; the JS object explicitly
returns description as a string before selector lookup. Both bridge implementation
files match the Host's checked-in source bytes. No native runtime source changed.

The installed Apple SDK lookup43623113279 independently verifies that UIKit's
ObjC API declares the description selector. That declaration is distinct from
the actual JS host-object string property. Do not infer a callable JS method from
the ObjC declaration. The lookup is not compilation or native execution proof.

Actual local results:

- Full UI declaration program: zero diagnostics; five exact negative diagnostics
  TS2322 twice,2339,2353,7006. Unknown props, wrong value/event types, missing Host
  method and implicit parameter are rejected without suppressions.
- Full native-api program: zero diagnostics; the same five plus2349/2351 reject
  calling the string description and constructing the constant timezone.
- Three Node tests passed: real Base64 library/production facade byte roundtrips
  without browser globals, native rejection/empty-vs-missing, and the actual Host
  global-installer JS preserving constants over colliding structs. Native module
  and metadata inputs are explicit fixtures; this is not Hermes/iOS execution.
- Real Metro0.87.1 compiled A/B of both existing UI and native-api templates.
  Bundles and source maps are retained under ignored build outputs. The final UI
  packages were rebuilt from the new source and staged into existing fixture paths.

The file facade now uses the already locked base64-js1.5.1 rather than browser
atob/btoa. Its native module interface is explicit instead of inheriting an
untyped requireNativeModule result. Empty data remains Uint8Array(0), missing
data remains null. The existing Base64 dependency is declared directly by the UI
package; no resolved package/native SDK version changed.

The existing fixture builder now calls the actual Metro CLI with structured
arguments, retains source maps, and reuses the existing deterministic ZIP writer.
Its recursive removal is restricted to the owned .build-probe directory. It no
longer relies on shell-built Python commands or machine-specific ZIP timestamps.
No automatic CI trigger was added. The existing manual Expo validation workflow
also runs strict native-api negative checks and both facade test files.

New production UI test
testProductionExpoHostFilesPreserveEmptyAndBinaryBytesThroughTheJSFacade imports
the actual package and requires a status emitted only after real JS→Expo module→
native roundtrips for zero, all256 byte values and131073 bytes, deletion and missing
file checks. This UI test is NOT_RUN until an authentic xcresult proves execution.
Strict types, Metro and Node fixtures do not satisfy that native consumer gate.

Reproduction after the existing pinned tooling install:

```powershell
node Scripts/Expo/check-ui-type-contract.mjs
node Scripts/Expo/check-ui-type-contract.mjs --native-api
node --test Scripts/Expo/Tests/host-services.test.mjs Scripts/Expo/Tests/native-api-globals.test.mjs
node Scripts/Expo/build-probe.mjs
```

Current hashes and raw local result identities are in
[the scoped evidence record](evidence/EXPO_SDK_TYPES_2026-11-14.json).
This is not a Developer Kit READY claim, every-public-native-adapter acceptance,
full extension parity or physical-device/signing proof.
