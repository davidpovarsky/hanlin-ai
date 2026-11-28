# Authenticated local Mac Host accounting

The existing GitHub accounting route remains schema 2 and retains its original 153-case contract and authenticated workflow identity. The local Mac route is schema 3. It verifies the original, completed 170-case producer (169 executed passes and the original opt-in long-job skip) without manufacturing a GitHub run, caller-credential observation, new test execution or acceptance for a later archive.

## Trust boundary

`record-local-mac-host-receipt.mjs` requires the SHA-256 of `preparation.json` from an independently authenticated owner/runner observation. Supply that already trusted value separately from the candidate input file. Computing a new digest from an untrusted candidate and immediately using it as the trust anchor defeats the purpose.

The original preparation receipt binds its exact controller, raw Host log, original native catalog, framework inventory, source commit, original archive and source fingerprint. The verifier requires one successfully completed original `prepare-runtime-host.sh` step. It checks all 170 unique, root-level spec-reporter case records, all seven terminal counts, the exact original skipped case, the packaged JITless fetch contracts and the final archive completion line. A summary, nested transcript, reuse message or `tests: passed` field alone cannot qualify.

The CLI then hashes the actual archive and all 16 original native source inputs, recomputes the original Host input fingerprint with the recorded Mac arm64 Node 24.5.0 toolchain, and calls the original `runtime_host_archive.py validate`. That validator retains package/lock, license, patched dependency, complete staged SDK and Host module-byte checks. Source fingerprint, archive, metadata, checkout identity and native input hashes are read again before the receipt is written. It never executes the retained controller and never invokes preparation, synchronization, tests, a native build or publication.

A compatible prepared checkout may have an unrelated later Git HEAD. The receipt keeps `head` equal to the authenticated **producer** source and records the inspected checkout separately under `verification.sourceCheckout`; exact canonical input-fingerprint equality is still mandatory. A changed authoring module, dependency, SDK input, fixture or preparation input cannot inherit the original producer result.

The original producer did not capture caller credential presence. Therefore `repositoryCredentialFreeHostTests.status` remains `NOT_RUN`. The full native framework inventory is attributed to its original verified reuse, not to a fresh compilation. Current framework/archive verification remains the responsibility of the unchanged native artifact consumers.

## Original Mac producer invocation

Prepare a small configuration file with explicit paths:

```json
{
  "repository": "davidpovarsky/hanlin-ai",
  "root": "/path/to/compatible-original-prepared-checkout",
  "preparation": "/path/to/original/preparation.json",
  "controller": "/path/to/original/stage_wave2_host.py",
  "log": "/path/to/original/logs/original-host.log",
  "nativeCatalog": "/path/to/original/original-native15-catalog-d13aed21.json",
  "nativeInventory": "/path/to/original/native-frameworks-before.json",
  "archive": "/path/to/original/build/runtime-host/RuntimeHostResources.zip",
  "metadata": "/path/to/original/build/runtime-host/host-metadata.json",
  "python": "/path/to/qualified/python3",
  "output": "/path/to/new/original-producer-accounting.json"
}
```

Relative paths resolve from the configuration directory. Existing output files are never overwritten.

```sh
/path/to/node-v24.5.0/bin/node Scripts/Runtime/record-local-mac-host-receipt.mjs \
  config.json INDEPENDENTLY_AUTHENTICATED_PREPARATION_SHA256
```

For the retained November 25 producer, the already observed preparation SHA is `7f30dbf3092177faa4788615ab115aa0fe87511963da3cdc7890b7f85c2527e6`, original source is `a146bc7af248e4fe4d518c74c810474d39baa93e`, original archive is `052c71626ea07c213e098ee04ebfa1a9ba528b8124accc6f35cd715e15f0e4dc`, and source fingerprint is `908f317442d73ce9a49b706174f7971bad72ba5c9d708f25fe7671eea437563f`. These identify the retained execution, not the resolver-cache derivative.

`verifiedReceiptAccounting(receipt, proof, {preparationSHA256})` recomputes schema-3 origin accounting from the raw preparation/controller/log/catalog/inventory strings. A consumer must supply its independently trusted preparation digest; the receipt's own accepted boolean is insufficient. As with the GitHub route, this origin check does not replace the consumer's actual artifact/source verification. The existing GitHub proof reader and merge gate remain GitHub-only; local evidence cannot impersonate an Actions check.

## Module derivative and full native catalog

The later authoring-cache derivative keeps a separate archive and qualification receipt. Its original 170-case partition is **17 freshly executed affected passes + 152 verified original passes + 1 original skip**, with the complete dependency/source closure recorded in `docs/ci/evidence/authoring-resolution-cache-20261125/host-case-reuse-closure.json`. Do not report 186 passes or claim the derivative executed all 170 cases. The original 052c producer metadata remains immutable.

After the source owner releases the prepared checkout, use the existing module-only synchronization plan and verify the actual new ZIP. `HanlinNodeHostSupport` packages that whole ZIP, so its identity changes even though the 15 framework binaries and four other support groups do not.

The supported **full** catalog path is the existing exporter with neither `--targets` nor `--without-host-support`:

```sh
python3 Scripts/SDK/native_artifacts.py export \
  --root FINAL_SOURCE_ROOT \
  --prepared-root QUALIFIED_COMPLETE_PREPARED_ROOT \
  --output NEW_OWNED_ASSET_DIRECTORY
python3 Scripts/SDK/native_artifacts.py verify \
  --catalog NEW_OWNED_ASSET_DIRECTORY/native-artifacts.json \
  --assets NEW_OWNED_ASSET_DIRECTORY
```

Export validates and packages existing artifacts; it does not compile them. Require exactly the 15 original framework targets and all five support groups, `scope: full`, and no missing targets. Compare every unchanged framework ZIP/native slice and all four other support records to the original qualified catalog. Only the Node support archive/content may differ. Preserve the original native producer provenance. There is no existing incremental/full-catalog merge subcommand; a selected NodeMobile export is not a full catalog.

The content identity hashes canonical sorted target-to-ZIP-checksum records for all 20 assets. A changed Node support checksum therefore creates a new tag, and **all 20 URLs** must use that tag. The original loader rejects mixed release identities. After the publication owner verifies the new complete asset set, the supported direct CLI is:

```sh
python3 Scripts/SDK/native_artifacts.py publish \
  --catalog NEW_OWNED_ASSET_DIRECTORY/native-artifacts.json \
  --assets NEW_OWNED_ASSET_DIRECTORY
```

Do not use `--allow-selected-targets`. This direct path checks ZIPs, refuses conflicting existing assets, uploads missing assets to the content-addressed release, verifies downloaded bytes and publishes the catalog. The separate GitHub publication workflow requires an actual successful producer run; do not supply an old or fabricated run ID for a local derivative. The SDK owner's temporary-root `validate_node_support` dependency-closure repair is also required before treating that original install consumer as verified. The canonical parity archive's prepared E2E copy remains a separate consumer gate.
