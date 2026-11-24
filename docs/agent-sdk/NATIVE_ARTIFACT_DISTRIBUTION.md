# Native SDK artifact distribution

The canonical source remains in the Hanlin repository. Native runtime engines are reused from their accepted producer; this pipeline packages existing prepared bytes and never compiles an engine.

## Current status

The frozen producer is GitHub Actions run [42926628418](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42926628418), source commit 4784dd99c3e5892ef726e7a3cce6587eb7847997. Its aggregate RuntimeCore archive was downloaded and independently matched the locked SHA-256:

    196a35562a31229b1bcf05afbe49f76470ced90a7fbf0494ecebd5c06d07440f

The real NodeMobile device and Simulator framework was repackaged by the new exporter and verified without rebuilding. `swift package compute-checksum` agreed with its ZIP SHA-256. This proves packaging, not a new runtime execution pass.

At this checkpoint, `docs/native-artifacts.json` deliberately says `unpublished`. No missing binary has a fabricated URL/checksum. The full Apple gate must export the original prepared 14 XCFrameworks and host support, publish them, then replace that catalog with the verified output.

Two older public `runtime-core-v1-...` releases contain aggregate RuntimeCore ZIPs. They do not provide the per-framework ZIPs required by SwiftPM. The frozen producer's Actions artifact was available on 2026-11-23 and was retained in the task cache; it is not treated as a permanent SDK download URL.

## Export once after original preparation

Run in the original Apple job after its existing Expo, NativeScript and RuntimeCore preparation:

```sh
python3 Scripts/SDK/native_artifacts.py export \
  --root "$GITHUB_WORKSPACE" \
  --output build/sdk-native-prepared

python3 Scripts/SDK/native_artifacts.py verify \
  --catalog build/sdk-native-prepared/native-artifacts.json \
  --assets build/sdk-native-prepared
```

Upload `build/sdk-native-prepared/` with the artifact name `hanlin-sdk-native-prepared`. Existing preparation must finish first. A missing framework, native slice, metadata tool, original wrapper or Python installer patch causes an explicit failure. The exporter does not insert placeholders or fall back to rebuilding.

The full export includes ReactNativeHeaders, React, ReactNativeDependencies, hermesvm, ExpoModulesJSI, ExpoModulesCore, ExpoModulesWorklets, ExpoUI, ExpoBrownfield, Libffi, TNSWidgets, NSCWinterTC, NodeMobile and Python.

Shared support is split so a selected runtime does not pull unrelated support:

| Archive | Original prepared files | Required by |
| --- | --- | --- |
| HanlinExpoHeaderSupport | ModularFrameworks, ReactModularHeaders | Expo and Native API targets |
| HanlinNativeScriptHostSupport | Core usage/closure, patched metadata compiler with builtin headers, original upstream and wrapper launchers | TNSWidgets, NSCWinterTC |
| HanlinNodeHostSupport | AI_HLY/RuntimeHostResources.zip | NodeMobile |
| HanlinPythonHostSupport | Vendor/Python/Python-VERSIONS | Python |

Python's standard library and original build helpers remain inside Python.xcframework. The prepared host-support validation retains Hanlin's original framework bundle-identifier and FMWK fixes.

ZIPs have stable entry order and timestamps, preserve native bytes, executable permissions and internal symlinks, and exclude only transient staging metadata/macOS sidecar files. The catalog records every ZIP checksum and native slice hash. Its release tag is derived from the complete asset content hashes.

## Publish the verified original output

After the original producer and its relevant gates succeed:

```sh
python3 Scripts/SDK/native_artifacts.py publish \
  --catalog build/sdk-native-prepared/native-artifacts.json \
  --assets build/sdk-native-prepared
```

The command creates a content-addressed `sdk-native-v1-...` release, uploads missing assets, refuses to replace differing immutable assets, then downloads each public URL to verify its bytes. Only after readback does the catalog become `published`.

The separate `publish-sdk-native-artifacts.yml` workflow can consume the retained artifact from a completed successful producer run. It verifies repository identity, commit and preparation input hashes before calling the same publisher. It does not dispatch builds or rebuild runtimes.

Copy the published catalog to `docs/native-artifacts.json` in the integration commit. The root manifest generator can then consume each record's `target`, `url` and `checksum`. Existing child manifests were intentionally not edited in this lane.

```sh
python3 Scripts/SDK/native_artifacts.py swift-targets \
  --catalog docs/native-artifacts.json
```

## Selected host installation

A pinned local source checkout uses the same canonical files. After the root generator selects the requested product closure, install only its managed native targets:

```sh
python3 Scripts/SDK/native_artifacts.py install \
  --catalog docs/native-artifacts.json \
  --root /absolute/path/to/installed/HanlinSDK \
  --cache /absolute/path/to/shared/native-cache \
  --targets NodeMobile
```

This downloads NodeMobile and its original RuntimeHostResources archive, without Expo headers or Python. Pure source products skip native installation entirely. The installer verifies checksums, archive paths and actual native slice structure before placing managed generated files. It refuses to overwrite unmanaged files and retains a resumable receipt.

Full hosts invoke the shared original build phases from Xcode, after native support is installed:

```sh
python3 "$HANLIN_SDK_ROOT/Scripts/SDK/native_artifacts.py" host-python \
  --root "$HANLIN_SDK_ROOT"

python3 "$HANLIN_SDK_ROOT/Scripts/SDK/native_artifacts.py" host-nativescript \
  --root "$HANLIN_SDK_ROOT"
```

Python invokes the original `install_python` helper with the host's Xcode output/signing environment. NativeScript invokes the original patched metadata wrapper; host build/output/SDK paths remain Xcode's values and source/tool lookup uses the SDK checkout. The metadata tool is the original prepared architecture-specific tool, with its original provenance.

These commands centralize implementation. An actual Apple host build remains the acceptance gate for metadata visibility, Python extension embedding, signing and execution.

## Measured SwiftPM behavior

The Oracle Swift 6.4.3 toolchain was used for actual remote HTTP Git consumer fixtures, not just manifest text assertions:

| Case | Observed result |
| --- | --- |
| Tagged dependency using unsafeFlags | PASS |
| Same dependency pinned to a revision | PASS |
| Same dependency installed by local path | PASS |
| Source-only product with an unused missing local binary target | Resolution failed before compilation |
| Source-only product with an unused remote binary target | Build passed, but SwiftPM still downloaded and staged the unused 5 MB native artifact |

The older PackageDescription documentation warns that unsafe flags make products ineligible as dependencies. The measured current toolchain did not reject these fixtures, so this work does not claim that all versioned use is forbidden. Existing absolute prepared header paths and host phases still require concrete original-host validation.

Publishing binary URLs alone does not deliver lightweight products: the actual consumer still downloaded an unused binary. The root generator therefore must prune targets and external dependencies to the requested transitive product closure. This preserves one canonical implementation while making an AgentCore/ChatUI-only installation independent of native runtime preparation.

Evidence and limits are recorded in [native-distribution-2026-11-23](evidence/native-distribution-2026-11-23/receipt.json). No new Apple runtime or physical-device success is claimed by the portable packaging and dependency tests.

## Original Apple producer integration

The original `.github/workflows/build-ios26-unsigned-ipa.yml` now exports the
complete 14 XCFrameworks and four support archives after its existing Apple
preparation steps. The simulator job owns `hanlin-sdk-native-prepared` when it
is selected; the device job owns it otherwise. The artifact is retained for
30 days with compression disabled because its contents are already ZIPs.
No additional runtime compilation or CI dispatch is introduced by export.

Both jobs already run the original `prepare-runtime-core.sh`. That script
verifies the frozen native identity, copies the verified Host archive, and
synchronizes current Host source modules against the unchanged dependency
closure. A full-validation run is not required just to export the prepared
SDK inputs. The exporter invokes the original archive validator with
`check_sources=True` before creating the Node support archive, so stale
Host modules cannot be published.

The original frozen run 42926628418 was checked against this source revision.
The dependency and patch closure matched. Exactly six Host `.mjs` modules
needed the existing source overlay; the synchronization preserved all 3,070
dependency/other entries byte for byte and invoked no builder. The focused
receipt is in
`evidence/native-producer-wiring-2026-11-23/frozen-host-source-overlay.json`.
This is archive reuse evidence, not native execution evidence.

The device, simulator and packaged-IPA scans now use
`Scripts/SDK/verify_bundle_resources.py` for the actual `AI_Hanlin` resource
bundle. It derives copied resources from the canonical Swift manifest and
compares every packaged file to its source hash. Main-app leftovers cannot
satisfy this check. Compiled localization is checked separately by the
existing localization validator against its SDK resource bundle. The
ios_system dictionaries and Python stdlib retain the original required host
locations and their existing validators.

The subsequent publication workflow still requires the producer run to
complete successfully before a public catalog can be marked published.
Exporting and retaining a prepared artifact alone does not establish Apple
build, simulator, host integration or visual acceptance.
