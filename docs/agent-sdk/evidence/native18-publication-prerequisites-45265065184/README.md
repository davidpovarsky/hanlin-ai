# Native18 publication and full-profile installation prerequisites

Reviewed source: **ade2f626e37102abde83050c94d524d19e0726bb**, intended producer run **45265065184**. Root owns the only watcher and will assign the single eligible artifact after terminal admission. This review made no run/API query, artifact acquisition, installation, publication, test execution or further deletion. The commands below are prepared and **NOT_RUN**.

## Eligibility and source binding

The original workflow exports from the verified RuntimeCore and prepared Expo/NativeScript trees into `build/hanlin-sdk-native-prepared`, runs the original archive verifier, and uploads exactly one artifact named `hanlin-sdk-native-prepared` with compression level 0. A successful export step within a failed overall producer remains ineligible for this release.

The assigned original terminal run must be SUCCESS at the actual frozen source and attempt, with its acceptance evidence admitted by root. Its unique unexpired prepared artifact must name the same run and source. The downloaded outer ZIP must match the GitHub byte count and SHA256, with safe unique paths and valid CRCs. No artifact ID or current expansion size has been guessed here.

The original prepared catalog must have producer source ade2f626, full scope, no missing targets, all 14 required frameworks and all four support groups. The content-addressed tag, URLs, ZIP checksums, archive locations and slice hashes use the original `native_artifacts.py` contract. Preserve an exact copy of the prepared catalog before the publisher changes its local state to published.

The complete source contract remains the existing **11 declared preparation inputs**. The original `verify_source_inputs` function binds them to immutable Git blobs and checks any materialized copies. It deliberately supports sparse source checkouts. The separately packaged metadata helper is not added to this set: the normal installed-source check binds it to the final SDK checkout, without a per-helper producer-byte claim.

Original producer export already calls `runtime_host_archive.py validate` against that producer's original Node Host source before exporting its support archive. The final full-profile installer calls the original Node source/archive validator again against the actual final SDK revision. No Node rebuild, npm operation or new archive schema is introduced.

## Existing commands and exact inputs

Use ubuntu-owned Git/gh and an owned release workspace beneath the release-readiness worktree. Let `PRODUCER_SOURCE` be an isolated sparse Git checkout at the exact ade2f626 SHA, borrowing the existing canonical Git object cache. It needs the original `Scripts/SDK/native_artifacts.py` materialized; its existing source guard reads all other required input blobs from Git. This avoids an extra full source checkout. Let `PREPARED` be the authenticated extracted payload directory containing the 18 compressed archives and catalog.

Before publication, call the existing source guard on that exact producer checkout. This invokes original functions without changing the prepared catalog's state:

```python
from pathlib import Path
import json, runpy, sys

source = Path(sys.argv[1]).resolve(strict=True)
catalog_path = Path(sys.argv[2]).resolve(strict=True)
native = runpy.run_path(str(source / "Scripts/SDK/native_artifacts.py"))
catalog = native["load_catalog"](catalog_path)
expected = "ade2f626e37102abde83050c94d524d19e0726bb"
assert native["source_commit"](source) == expected
assert catalog["sourceCommit"] == expected
assert catalog["state"] == "prepared" and catalog["scope"] == "full"
assert catalog["missingTargets"] == []
assert len(catalog["artifacts"]) == 14
assert len(catalog["supportArtifacts"]) == 4
assert set(catalog["requiredTargets"]) == set(native["TARGETS"])
assert {x["target"] for x in catalog["artifacts"]} == set(native["TARGETS"])
assert {x["target"] for x in catalog["supportArtifacts"]} == set(native["SUPPORT_GROUPS"])
assert native["verify_source_inputs"](catalog, source) == expected
print(json.dumps({"sourceCommit": expected, "declaredInputs": len(native["INPUTS"])}))
```

After root admits producer/artifact eligibility, the original publisher performs its archive verifier before any release mutation:

```bash
python3 "$PRODUCER_SOURCE/Scripts/SDK/native_artifacts.py" publish \
  --catalog "$PREPARED/native-artifacts.json" --assets "$PREPARED"
```

Do not add `--allow-selected-targets`. The publisher refuses conflicting immutable assets and independently reads every exact public payload URL after upload. It reads back one payload at a time and deletes that temporary download before the next. A separate invocation of the same archive verifier is available as `verify --catalog ... --assets ...` when publication is not yet admitted; it need not be redundantly run immediately before the publisher's own verifier. Retain the publisher output and final catalog. Verify the resulting release/catalog readback after publication; there are 18 payload assets plus the catalog.

Integrate the exact published catalog as `docs/native-artifacts.json`. Catalog publication alone does not affect `generate_manifest.py`, which does not read that catalog. Regenerate only when actual package manifests or relevant generated-source inputs change. If an identical content-addressed release already exists, the original publisher retains its original catalog producer after matching preparation inputs and every artifact record; never rewrite that producer to a later SDK source.

Once the final SDK source is frozen and published to Git, create one fresh owned full-profile host. Its `HanlinSDK.lock.json` contains the full immutable final revision and every product name from that revision's canonical inventory:

```json
{"revision": "FINAL_40_CHARACTER_SDK_COMMIT", "products": ["ALL_44_EXACT_NAMES_FROM_THE_FINAL_INVENTORY"]}
```

The array above describes the input source; populate it mechanically from `docs/agent-sdk/unified-package-manifest.json`, not with that placeholder. Use the original final-revision installer, followed by its original check:

```bash
python3 "$FINAL_SOURCE/Scripts/SDK/install.py" \
  --host-root "$FULL_PROFILE_HOST" --source-cache "$CANONICAL_SOURCE" \
  --cache "$OWNED_NATIVE_CACHE"
python3 "$FINAL_SOURCE/Scripts/SDK/install.py" \
  --host-root "$FULL_PROFILE_HOST" --check
```

The installer verifies exact requested products, generates its profile from the pinned checkout, checks the AppIntents HostResources projection, installs managed native payloads and writes its receipts. `--check` already calls original `verify-source` for the selected native targets and checks installed paths. Do not add a redundant immediate second invocation of that same source guard. Capture the actual final profile, receipts and source identity. This is installation acceptance; app/native execution remains separately source-bound.

The three existing isolated Host descendants keep their selected profiles and currently have zero managed native targets. Their final wrapper/check calls update source in place after the final freeze; they do not each require another Native18 expansion. Their source trees at ade2f626 contain approximately 26.8–26.9 MB each, already represented by the exact record inventories.

## Space plan

**All 18 payloads must coexist in the final full-profile installation. A second complete expanded staging tree is unnecessary.** The original installer extracts one asset into a temporary directory under the SDK destination, validates it, and renames it into place on the same filesystem. A fresh destination has no old native backup tree. It preserves each completed receipt so interruption can resume safely.

Measure these quantities from the assigned original archive before payload extraction:

- **Z:** outer GitHub ZIP bytes.
- **C:** combined compressed sizes of the 18 inner archives and catalog.
- **N:** installed expansion of all 18 payloads, including filesystem block rounding, implied directories and symlinks.
- **M:** largest compressed inner archive, for the publisher's serial public readback.
- **S/G:** final source checkout plus actual small Git/profile/compiler bookkeeping.

The outer artifact uses compression level 0. Python `ZipFile.open` can expose each nested archive for central-directory inspection without first writing a second copy of the expanded frameworks. Use the real nested inventories to calculate N; the historical approximately 184 MB outer artifact is not this producer's size. Preserve the original outer ZIP and catalog.

On `/mnt`, retain Z + C and hardlink the authenticated inner archives into the exact owned cache filenames `checksum-archive`. This avoids an extra C allocation while preserving the original installer checksum logic. The fresh full installation then needs approximately **Z + C + S + N + G**, with directory/metadata headroom. It does not need Z + C + S + 2N. The source-only producer checkout is small; the conservative entire AI_HLY/Packages/bootstrap/helper Git envelope for a full checkout is **91,078,170 bytes in 2,984 records**, including one original 112-byte symlink. This is not a final allocated-size claim.

**`/tmp` is a separate filesystem.** The publisher uses it for at most M bytes of readback at a time; original Node validation uses it for its 132 tracked source files, **607,496 payload bytes**. Check both filesystems before their respective phases. The time-specific observed free values are recorded in `space-plan.json`, not reserved capacity. No current install-size admission is claimed before the actual eligible ZIP and final source exist.

## Additional root-owned recovery candidates

Three small duplicate selections under root's central `build` directory were compared byte-for-byte with retained authenticated original ZIP members: one extracted build log, one three-file extraction, and one 30-file extraction. Together they occupy **32,337,920 allocated bytes**. Their source artifact identities, every exact path/member/hash and the preserved ZIP/receipt paths are in `root-duplicate-inventory.json`. They remain **inventory only**, pending explicit root disposition.

No sole original job log, ZIP, acquisition receipt or committed evidence is nominated. The 76 MB schema-probe build directory is also excluded because it contains the original executable named by its result receipt and no byte-identical preserved source for that binary was established. Nothing further was removed.

## Future SDK02 Swift-only integration

The inspected candidate846ca37a changes six production Swift files in AgentCore/ChatCore and changes none of the 11 native preparation inputs or original Node Host/validator sources. Its Native18 dependency can therefore reuse an eligible ade2f626 publication under the existing source guards. Preserve ade2f626 as the actual catalog producer; record the later installed SDK commit separately.

This permits dependency-asset publication while the separate SDK02/Motion gates remain pending, as authorized by root. It does not label the later provider, engine, application, UI or runtime acceptance as passed. Final integration still needs its own affected source verification and final pinned installation.
