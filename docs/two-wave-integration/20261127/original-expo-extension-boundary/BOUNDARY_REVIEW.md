# Original Expo Widgets extension boundary

## Outcome and scope

This is a source repair for the reproduced device packaging failure, with portable source controls passed. It is **not a native build, widget parity, or device closure PASS**. The original App Store/device Mach-O validator, original application test selectors, package pins, and original Expo Widgets JSC renderer remain in force.

The source base is `a729bc6380fe08807d67d83f916b9bfda9cc1051`. The sealed source manifest contains 65 paths: 33 tracked changes and 32 added original native modifier source files. `Packages/HanlinPlatform` has no changed paths in this candidate. The exact source manifest and patch accompany this report.

## Reproduced failure

On source `f768d634bfa8a102cf63b32c7ab9d129cafc671d`, device run `45949460695`, job `140341929366`, built the application successfully and then failed `Validate packaged IPA dyld closure`. The original report inspected 93 binaries and found 11 forbidden transitive loads, six unsafe dylibs, and no missing dylibs. The widget extension linked the full React/Hermes/Expo Core runtime through its original widget package product. The real linker command already requested application-extension mode; the validation failure was not a missing validator flag.

The retained `widget-native-mach-o.json` has SHA-256 `b14da853e9d117ab9f0dd6457feae522f3d3b2ee16c0738e88316474440b5247`. The original validator `Scripts/Widgets/audit-native-products.mjs` remains unchanged, SHA-256 `26d0724106dc575d0a38e3661afce39edd2829070219cb0eaeab12ba9bbce246`.

The actual pinned upstream podspec/plugin lookup is retained. The upstream widget autolinker disables application-extension-only checks for app runtime dependencies; this candidate does not use that workaround.

## One original module, disjoint host ownership

| Product | Target ownership | Intended consumer |
| --- | --- | --- |
| `HanlinExpoWidgetsExtension` | `ExpoWidgets` | Both shipping WidgetKit extensions and their shared widget UI |
| `HanlinExpoWidgetsOriginal` | `ExpoWidgets`, `ExpoWidgetsHost` | Shipping applications and original app test consumers |

`ExpoWidgets` continues to define the original JSC runtime, resources, timeline, native views, state, App Intent actions, interaction events, installation binding registry, and nominal `LiveActivityAttributes`. It uses native SwiftUI props and view primitives, contracts, and Apple frameworks. It compiles with `-application-extension`.

`ExpoWidgetsHost` owns exactly six original files, selected at their existing source paths: `LiveActivity.swift`, `LiveActivityFactory.swift`, `WidgetObject.swift`, `WidgetsExceptions.swift`, `WidgetsModule.swift`, and `WidgetsRecords.swift`. It retains their real Expo Core/React/ExpoUI dependencies and original C++ import flags. Source ownership is disjoint; there is no second implementation or second binding registry. Resources remain owned by `ExpoWidgets` and its existing `Bundle.module`.

Cross-target access uses package access. The original Activity attributes stay defined in `ExpoWidgets`; their existing fields gain package visibility and an explicit same-field initializer. Shared interaction constants move once into the shared event file with unchanged strings. The app provider registers the same module under the original JavaScript name `ExpoWidgets` through `ExpoWidgetsHost.WidgetsModule.self`.

The canonical SDK generator now wires the extension product to both widget hosts and preserves the original app product on app consumers. It removes only the app producer's C++ import flag pairs from the extension hosts, preserving their unrelated settings and extension-only enforcement. Its target graph guard rejects an extension path reaching Host, full Runtime, React, Hermes, Expo Core/JSI/Worklets, ExpoUI, or the other enumerated app modules. The original binary validator remains the final authority for the built closure.

## Original native view coverage

The existing primitive module contained 97 original built-in modifier registrations. The actual pinned original registry contains 164. The candidate restores all 164, including 37 missing native types from 32 original files. The registry plus these 32 sources were compared against both the installed pinned Mac package and the actual npm publication: all 33 original input files match byte-for-byte.

The publication is `@expo/ui` 58.0.29, tarball SHA-256 `559c84d9d72234fb5df033794e94dfb04cd6f99989f14685c3abbb397dc3f37c`. Each imported source has its original hash, type mapping, and local adaptation recorded. Thirty files need only their import substitution. The two worklet-related files retain the original native event path and explicitly reject a supplied non-null JSI worklet reference.

The original `WidgetsViewRenderer`, original view cases, keyed child identity, DynamicView identity, native button/toggle action handlers, and JSC runtime remain. The only removed renderer branch is the non-intent Button fallback below iOS 17, unreachable at the package's unchanged iOS 27 deployment floor. This candidate does not replace the original renderer with `HanlinExpoWidgetNative`.

Prepared widget admission stays at its original 97 built-in names plus its four existing special modifiers. Its immutable context mode, exact verified resource membership, and registration check prevent the expanded native registry from widening the prepared format. Original raw JSC props use an explicit original context and retain the original file/asset image behavior.

The original `WorkletCallback` is a SharedObject holding a real Worklet and calls the app context's UI WorkletRuntime. The original generic Worklet conversion requires an actual Worklet instance; it does not construct one from JSON. The extension adapter does not create a fake runtime or callback. A non-null bound-worklet/shared-state input is rejected at the raw JSON boundary. The full application retains genuine ExpoUI/Core worklet support. Exact upstream declarations are retained as source evidence; this is not an execution claim.

## Mechanical preservation and provenance corrections

Sixteen selected original file bodies are mechanically equal after the explicitly recorded import/access normalization. These include all six Host implementations (the shared event constants are accounted for separately), the binding/state implementations, native toggle, JSC runtime, App Intent, timeline provider/entry, utilities, and child/dynamic identity. The receipt records each exact before/after source hash and the comparison boundary. Other intentionally edited files are reviewed as explicit diffs rather than incorrectly reported as identical.

The canonical generator preserves all 532 original application source paths and the complete application resource arrays. The source-impact receipt records this equality.

The pre-existing upstream-source manifest had stale local hashes for eight already committed original widget files. Their actual baseline Git hashes, former recorded hashes, and paths are retained. This candidate updates those local hashes and the hashes of its current adaptations, preserves upstream blob/publication identities, and adds the 32 pinned original rows. Its native link status explicitly requires a current native build. The original runtime producer must regenerate its native-source receipt; this source repair does not hand-edit a producer result or label an old native result current.

## Executed portable validation

The original canonical `generate_manifest.py` completed successfully. The first `update_project.py` invocation stopped because this isolated sparse worktree omitted the unchanged canonical `Localizable.xcstrings` input. That original failure is retained. The exact committed 662,667-byte file was restored, hash `9437aa101dd2d12ad2e39471c6f76171750e6f4e2c83f01f21bbe47e1ef0186e`; no product source repair was needed for that environment issue.

The continued original commands passed: `update_project.py`, `generate_manifest.py --check`, and `update_project.py --check`.

The original focused unittest discovery commands passed nine methods, with no failures or skips: three `test_widget_cxx_imports.py` methods and the unchanged six `test_host_link_ownership.py` methods. The C++ controls retain the app import assertions, verify the new pure native extension ownership, and exercise forbidden graph edges and policy-boundary negatives. The unchanged ownership suite verifies the existing host/unknown-product/object preservation contract. Raw stdout, stderr, commands, timing, and receipts are included.

## Native acceptance still required

The actual historical 866 SDK manifest records 392 input paths. Twenty-two candidate paths intersect that recorded set; the new source collector must also evaluate the complete current closure. This is a measured historical input-set comparison, not a new fingerprint or Host acceptance result.

After integration, the original runtime producer/fingerprint and Host validation must refresh. Original simulator build/tests and device archive/packaged dyld validation must run on the integrated source. App Intent extraction, actual Swift compilation and cross-module access, real widget views/actions/Activity identity, and the absence of forbidden binary loads remain required native outcomes. The Mac/native lane and root own those executions; this source lane has launched none.
