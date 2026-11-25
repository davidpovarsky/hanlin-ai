# Host module synchronization and evidence reuse

## Scope and current status

This is a source review and execution plan, not a claim that a new Host archive or native acceptance run has executed. The target is Wave2 `8f26449ca98911fb197fc332606794c263e68a51`. The current Mac checkout and sealed Main10 products at `705163fb2a952522ca6cbfdcdebddd8bd6b22532` remain untouched until their owner releases them.

The only executable Host change is the operation-local resolver cache in `AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs`, SHA-256 `6eb7130890499768b72990cc48cf84b515232635bf00b4ca023bcc1b161182fc`. It is identical to the genuinely measured/tested donor `707f9c2e3ea8488fafb284e14a7b7636ebb25a48`.

## Authentic Host case partition

The original a146 preparation receipt SHA-256 is `7f30dbf3092177faa4788615ab115aa0fe87511963da3cdc7890b7f85c2527e6`; its full Host log SHA-256 is `715c163601a4873f3d0e2be71be385e8735fc3f7f7007ae6ac0aded6802a4181`. The original `node --test Tests/*.test.mjs` result is 170 cases, 169 passed, zero failed, one skipped.

| Partition | Cases | Evidence at the target |
| --- | ---: | --- |
| Authoring and canonical SDK resolution | 17 | Fresh original tests passed on identical changed module bytes, Node 24.5.0 with `--jitless`, actual TypeScript 6.0.3; receipt `8b75ac33bb634e8b7de5f03d06638f2bb4252e68250acc665d39f3a3b39d9b0b` |
| Other default Host cases | 152 | Original authentic passes remain attributable to a146; source/input closure qualifies their selective reuse |
| Original long-running job opt-in | 1 | Still skipped; `HANLIN_RUN_LONG_JOBS=1` was not supplied |

These are a partition of the original 170 cases. They are not 186 new passes, and they do not describe a fresh full-suite execution at the target. The skipped identity is `actual Node job crosses 300 seconds with no hidden deadline`.

`host-case-reuse-closure.json` retains all 170 case names, the 17 exact affected test source identities, and all 135 actual prepared Host-source hashes. Both original pre-Host and post-Host source manifests agree with the a146 Git blobs. At the target, 134 files remain byte-identical, including every test, fixture, package lock, patch manifest and other Host module. Only `miniapp-authoring.mjs` differs.

The changed statements are inside private `parseProject`; imports and module initialization are unchanged. The two original default-suite files that call `runMiniAppOperation` are exactly the 14-case authoring file and the three-case SDK-resolution file. Other Host production modules do not import this authoring module. `miniapp-native-presentation.integration.mjs` is an additional affected consumer outside the default 170-case command; this review does not invent an execution or reuse claim for it, the separate ScriptWidget authoring suite, shipping-example suite, or native MiniApp E2E.

## Main Sidebar10 boundary

The complete 705-to-target tracked diff is the authoring module plus board/evidence documentation. Sidebar Swift source, the five unit cases, five UI cases, routing, fixtures, package graph and Xcode configuration are unchanged. The selected cases exercise actual history, profile, drafts, search, row actions, native back, scene reactivation and Hebrew layout; they do not request MiniApp authoring.

However, Host resources are not globally unreachable: `RuntimeLifecycleBridge.prepareApplication` calls Node `healthCheck`, and `NodeRuntimeService.prepareHostRuntime` hashes the entire ZIP and extracts it to `host-<archiveHash>`. A newly synchronized archive therefore has a new extraction identity. Any authentic future 705 Main10 pass may be recorded as selectively reused evidence for its unchanged sidebar assertions. It must not be relabeled a fresh target run, fresh Host-extraction/cold-start proof, a MiniApp authoring E2E pass, or physical-device acceptance. A build-only pass is not ten case passes. Record the actual terminal case count and result before applying this closure.

## Existing supported archive operation

The existing `Scripts/Runtime/runtime_host_archive.py:synchronize_archive` explicitly supports updating top-level source modules over a validated locked Host archive. `prepare-runtime-core.sh` uses this same operation after copying the producer Host resource. No compiler, npm install, SDK expansion or native framework rebuild is required when dependency/SDK inputs match.

Required existing bytes:

| Input | Identity |
| --- | --- |
| Original application Host ZIP | `052c71626ea07c213e098ee04ebfa1a9ba528b8124accc6f35cd715e15f0e4dc`, 81,813,655 bytes |
| Original SDK manifest | `02e57f0738b55b1e0d9e6bd2c0ea2d8a2fa8cd99636179c8085dec2d965201ea` |
| Original SDK input fingerprint | `ba577dec2da7ecce14ed8adef5b3879c8b4229e0fc9453d4e6d123a4002288c7` |
| New authoring module | `6eb7130890499768b72990cc48cf84b515232635bf00b4ca023bcc1b161182fc` |

The original ZIP is currently `/Users/m1/builds/hanlin-wave2-a146bc7a-20261125/AI_HLY/RuntimeHostResources.zip`. Preserve that original producer proof and the baseline archive. Do not write the active 705 checkout or its derived products.

After the owner releases the prepared checkout and installs the exact final source:

1. Freeze the current Git revision, materialized Host files, original ZIP, original producer metadata, generated SDK-documentation overlays and native-framework inventory. Verify all relevant source bytes against the target and the original prepared inputs. Preserve the generated overlays; replacing them with older tracked documentation can change the SDK fingerprint.
2. Run the original `stage-sdk.mjs --fingerprint` using Node 24.5.0 in the actual prepared repository. Require the existing SDK fingerprint above. The authoring module, board/evidence documents and parity demo archive are outside this SDK fingerprint. Fail on any unexpected fingerprint change rather than rebuilding dependencies incidentally.
3. Run `validate_archive(original_zip, host_source)` with its default `check_sources=False`. Require no dependency, license, patch or SDK-integrity errors. Separately compare the complete top-level module inventory and require the only original-to-target module-content mismatch to be `miniapp-authoring.mjs`.
4. Copy the original ZIP into a new task-owned staging directory. Invoke the original `synchronize_archive` on that copy. Supply a builder callback that raises on unexpected dependency drift; the intended branch must return `updated source modules with unchanged locked dependencies`. This preserves the original validator rather than substituting another archive schema.
5. Run the existing full `validate_archive(..., check_sources=True)` and the original CLI `validate` on the staged output. Compare normalized ZIP-member inventories and uncompressed SHA-256 values: only the authoring module's contents may differ; all SDK/dependency/non-module bytes and their original modes must match. The original writer rewrites every top-level `.mjs` entry, so record its resulting metadata instead of claiming all unchanged modules retain identical ZIP timestamps/modes or compressed byte offsets.
6. Bind the new archive hash to the exact target/module hash and the authentic case partition above. Record the original packed JITless fetch smoke as reused only after its complete module/dependency input closure remains identical. The 17 current tests were executed against identical extracted module/SDK bytes; do not rerun them solely because the outer ZIP has a new hash.
7. Only after successful staging, atomically install the qualified derivative into the released application source's `AI_HLY/RuntimeHostResources.zip`. Keep the original producer archive and all old receipts. At the next actual app archive/export, verify the resource bundle used by `HanlinApplicationResources.bundle` contains the new ZIP bytes, and bind that hash in the final prepared-input/archive receipt.

Illustrative call to the actual helper, inside a bounded owner controller after the gates above:

```python
spec = importlib.util.spec_from_file_location(
    "original_runtime_host_archive", repo / "Scripts/Runtime/runtime_host_archive.py")
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)
assert original.validate_archive(staged_zip, host_source) == []

def refuse_unplanned_builder():
    raise RuntimeError("Dependency or SDK drift; module-only plan no longer applies")

result = original.synchronize_archive(staged_zip, host_source, refuse_unplanned_builder)
assert result == "updated source modules with unchanged locked dependencies"
assert original.validate_archive(staged_zip, host_source, check_sources=True) == []
```

Use a measured phase budget: two compressed copies of the 81,813,655-byte archive plus approximately 32 MiB for module metadata/manifests/log variance is 197,181,742 bytes before actual concurrent-growth and OS margins. Recompute against `df -k /System/Volumes/Data`, memory pressure and currently active producers. No full SDK extraction or fresh large source/cache copy is part of this phase. The owner must still preserve the active native checkout's freeze.

## Metadata and distribution consumers

- `build/runtime-host/host-metadata.json`, `runtime-host.sha256` and the old producer ZIP describe the genuine a146 full Host producer. Preserve them together. The new source fingerprint will differ. Do not replace their source/archive hashes and copy the old `tests: passed` marker as though a fresh full producer ran. The application derivative gets a separate qualification receipt with original/fresh/reused case origins.
- `runtime_host_archive.reusable_prepared_archive` intentionally requires matching source and archive hashes. A later invocation of the full Host producer can legitimately reject the old producer cache; this plan does not weaken that gate. `RuntimeManifest.json` comes from the unchanged runtime dependency lock and does not carry the Host ZIP hash.
- `assemble-runtime-bundle.sh` and `record-upstream-receipt.mjs` consume producer checksums/metadata. They cannot silently be pointed at a derivative with stale producer metadata. The existing upstream accounting also hardcodes the older 153-case count and requires a GitHub execution identity; it cannot authenticate this actual 170-case local Mac origin without an explicit separately reviewed accounting update. Do not spoof CI identity or claim that gate passed.
- `HanlinNodeHostSupport` is the entire `AI_HLY/RuntimeHostResources.zip`, as declared by `Scripts/SDK/native_artifacts.py`. Its old support ZIP identity is invalid for the new module even though all 16 declared native preparation inputs and the 15 native frameworks are unchanged. For a selected Node support export, the existing command is `python3 Scripts/SDK/native_artifacts.py export --root <final-source> --prepared-root <qualified-prepared-root> --output <new-owned-output> --targets NodeMobile`, followed by the existing `verify` command. It validates and packages existing native slices; it does not build them. This yields a selected-target catalog, not a complete 15-target catalog. The existing full catalog requires one content-addressed release identity for every asset URL, so a selected export must not be mislabeled as a complete SDK distribution. Root/SDK owner must perform the original required full-catalog binding/publication/readback stage before making that claim.
- A concrete existing SDK install consumer gap needs repair before ordinary-dependency acceptance: `native_artifacts.validate_node_support` materializes only the validator and tracked Host tree, but the validator now invokes `Scripts/MiniApps/stage-sdk.mjs` from that temporary repository to compute the SDK fingerprint. That script and its required fingerprint inputs are absent. Validation from the full prepared checkout does not have this missing-input problem. This source finding is separate from, and is not repaired by, the resolver optimization. It has been handed to the SDK owner; no installed-source acceptance is inferred here.

## Parity fixture consumer

Canonical `DemoMiniApps/hanlin-script-parity.hanlinNativeScript` at the target is 7,428 bytes, SHA-256 `089678e1b8fa03af23130e3b48fd0d75f394274c9d75e8959ca19e1d618988b8`.

The original `node Scripts/NativeScript/prepare-production-package.mjs` copies it to `build/NativeScriptE2E/hanlin-script-parity.hanlinNativeScript`. That script recreates the entire owned E2E preparation directory and catches copy errors, so run it only after the fixture owner releases the directory and verify the destination hash explicitly; exit zero alone is insufficient. The later original simulator-fixture staging consumer must receive that exact prepared file. Main Sidebar10 does not use this fixture, and an old copied fixture or previous parity failure is not a new parity pass.

## Handoff

No archive sync, catalog export, source switch, native build/test or release/workflow mutation was performed for this plan. Root owns those already-authorized concrete stages. Preserve the authentic 17 current passes and 152 prior passes; use their exact source/input closure and keep the original skip visible. Archive packaging, ordinary SDK installation, future native E2E and physical acceptance retain their separate actual-result boundaries.
