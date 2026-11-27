# SDK19 original prepared native reuse for release149101

This read-only qualification observed integration source `84d1a85cbf5dfc567f8f3ff0caa941fd14565b17` and the existing149001 donor. It did not edit either checkout, invoke a compiler/test, publish artifacts, or alter original catalog state.

## Decision

The existing local native frameworks and host support can feed the release-owned Xcode build. The normal direct Xcode/SwiftPM graph uses local `.binaryTarget(path:)` declarations and does not load `docs/native-artifacts.json`. The published-only `verify-source` command is called by the separate SDK installer, not this build.

Keep the old published catalog unchanged. Preserve and identify the genuine SDK19 catalog as **prepared**, source `a2c8a1b1be746461272ba77254603304567c309d`, SHA256 `3a8dc08f21556547720111e3ad31df314458f5cf75428adf2d69450965036a0d`. Do not change its status or original hashes to make the unrelated published-only checker succeed.

## Actual checks

- The existing original `native_artifacts.verify_source_inputs` verified all16 declared preparation inputs against the integration source and its pinned Git blobs.
- The original `framework_libraries` validated all15 actual donor frameworks, Mach-O/static library presence, real iOS device/simulator slices, framework bundle identities, platform and architecture records. All36 library records, including SHA256 of native bytes, match the SDK19 prepared catalog.
- The original `support_paths` passed: all5 support groups exist; the NativeScript metadata generator matches original provenance SHA256, its source patch and launch wrapper are valid, and the Python bundle compatibility patches are present.
- Widget bundle, layout registry, Info.plist and README bytes are unchanged. Only the original runtime receipt differs; the integration source carries the genuine SDK19 prepared receipt.
- The original retained SDK19 Host ZIP has81824721 bytes and SHA256 `7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc`.
- The original Host validator passed all locked dependencies, dependency patches and all SDK manifest members against current integration inputs. Computed SDK input identity is `ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2`.
- Full source validation reports exactly one authored module difference: `miniapp-authoring.mjs`. The integration retains the shipping per-program TypeScript resolution caches; SDK19's raw archive predates that source-only optimization. Synchronize this module through the original helper before packaging.
- The current root and child SwiftPM declarations use bare `-DWORKLETS_VERSION=0.13.0`. The prior donor used quoted0.13.1. This correction belongs to the authored HanlinExpoWorklets target, which the new consumer build must compile normally. It does not require rebuilding the15 vendor frameworks. The original SDK18 consumer object and response evidence in `8ac230b:docs/miniapp-sdk/evidence/primary-sdk-consumers-and-packages-attempt18-20261125/` proves the corrected bare version.

The comparison is not a claim that the donor contains every byte of the original SDK19 ZIP archives. Archive hashes differ for ExpoModulesJSI, ExpoUI, ExpoAsset and Widget/Node support. Genuine producer receipts retain their original inputs. The local framework qualification records the actual binary and layout boundary and the original support validator result.

## Required release-owned overlay

After the final integration Git source is materialized in the release clone, copy the original retained SDK19 Host ZIP to the clone only:

```sh
scp -q /mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt19/files/build/runtime-host/RuntimeHostResources.zip scaleway-mac:/Users/m1/builds/hanlin-testflight-149101-20261125/source/AI_HLY/RuntimeHostResources.zip
```

Then use the original helper with a fail-closed builder callback. Run this on the Mac with the release's pinned Node24.5 executable on PATH (the helper uses `node Scripts/MiniApps/stage-sdk.mjs --fingerprint`). The existing helper preserves the verified frozen dependency/SDK member bytes, replaces only top-level authored source modules, and validates the result. This is source synchronization, not native compilation or npm installation.

```python
import importlib.util
import hashlib
from pathlib import Path

root = Path("/Users/m1/builds/hanlin-testflight-149101-20261125/source")
archive = root / "AI_HLY/RuntimeHostResources.zip"
source = root / "AI_HLY/Downstream/RuntimeCore/Node/Host"
spec = importlib.util.spec_from_file_location(
    "hanlin_release_host", root / "Scripts/Runtime/runtime_host_archive.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def refuse_rebuild():
    raise RuntimeError("Frozen SDK/dependency closure changed; no rebuild authorized by this reuse step")

errors = module.validate_archive(archive, source, check_sources=False)
if errors:
    raise RuntimeError("; ".join(errors))
print(module.synchronize_archive(archive, source, refuse_rebuild))
errors = module.validate_archive(archive, source, check_sources=True)
if errors:
    raise RuntimeError("; ".join(errors))
print("Full current Host source validation passed")
print(hashlib.sha256(archive.read_bytes()).hexdigest())
```

Record the newly overlaid archive hash in the release receipt. Preserve the original SDK19 Host metadata as historical provenance; do not copy its tests-passed fields onto the new archive as fresh execution. The final app build, focused tests and release smoke remain owned by the integration agent.

No native archive regeneration, broad dependency preparation, npm resolution or modification of the prior donor is needed for this path. The external notification lane's newly restored Host is SDK20, so this qualification deliberately uses the exact compatible SDK19 archive plus current authored module synchronization.
