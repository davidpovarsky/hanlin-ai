# Guarded Native publication and immutable installation

These commands are prepared, **NOT_RUN**. Producer 45238831508 failed and its prepared artifact 14850817502 is permanently ineligible. Parent owns the necessary continuation 45246711373 at 36d3c51bdba93ada2c2722ed0e9b99109d84a616, its terminal result and sole artifact-acquisition assignment.

## 1. Successful producer and single acquisition

Require the assigned continuation run 45246711373 to be completed/success in davidpovarsky/hanlin-ai with head 36d3c51bdba93ada2c2722ed0e9b99109d84a616. It was only in progress at this update; do not acquire its prepared artifact yet. Export success from a failed run is insufficient. Reconcile actual selected acceptance identities/arguments before acceptance.

From the owner's terminal original run/jobs/artifact indices, select exactly one unexpired artifact named hanlin-sdk-native-prepared. Verify workflow_run identity/source, size and advertised SHA256. Its ID/digest stay unset until admission. The sole assigned acquirer can then fetch its raw ZIP once:

    gh api repos/davidpovarsky/hanlin-ai/actions/artifacts/QUALIFIED_ARTIFACT_ID/zip > prepared-original.zip

Verify outer size/digest, all ZIP CRCs and safe paths before extraction. Do not also invoke gh run download for the same artifact. Original export location is build/hanlin-sdk-native-prepared; the artifact contains native-artifacts.json and exporter ZIPs.

Check disk/memory before large extraction. Use an owned isolated worktree at the qualified producer SHA. Run Git/gh as ubuntu; preserve other branches/worktrees. Oracle origin has mirror=true: use the established per-command mirror=false override and explicit branch refspec for later authorized pushes; no global config changes.

## 2. Exact catalog and archive checks

Require sourceCommit=36d3c51bdba93ada2c2722ed0e9b99109d84a616, scope=full, missingTargets=[], exactly 14 unique original framework and four support records. Require the complete eleven-name inputSHA256 set to match exact Git and materialized source through the original verify_source_inputs guard. Retain the independently checked metadata helper hash from qualification.json. The bounded review is retained in metadata-helper-boundary.json: the helper is source-selected for the later Host metadata phase and is not a Native18 preparation/archive input. The normal shared installer checks that source. No per-helper runner-byte claim or additional publication gate is introduced.

With PREPARED set to the authenticated extraction directory, run the original source's verifier:

    python3 Scripts/SDK/native_artifacts.py verify --catalog PREPARED/native-artifacts.json --assets PREPARED

This validates size/hash, archive paths, plist and native slice hashes. Preserve original metadata-tool source/generator/architecture provenance. Original Node Host archive/source validation remains required during installation; no replacement fixture or native rebuild is involved.

## 3. Immutable publication

Only after the producer and original acceptance are eligible:

    python3 Scripts/SDK/native_artifacts.py publish --catalog PREPARED/native-artifacts.json --assets PREPARED

Do not use --allow-selected-targets. The original publisher derives sdk-native-v1-<64hex>, rejects differently hashed/sized existing assets, uploads missing archives and anonymously downloads/readback-verifies all 18 URLs. Only then does it mark and upload/reconcile the published catalog.

The CLI does not query producer completion itself; the preceding successful-producer guard is mandatory. The existing publish-sdk-native-artifacts workflow implements that guard, but need not be registered/dispatched merely to run the equivalent original CLI route on Oracle.

Integrate the resulting published catalog into docs/native-artifacts.json on an isolated descendant, preserving its producer sourceCommit. Use the canonical generator for any required manifest update, inspect the exact diff, commit/push and allow parent integration. Call the resulting full 40-character source commit FINAL_SDK_SHA. Neither the compared 39a/4c7 source nor continuation 36d presently contains a published catalog; none is a final installation pin.

## 4. Real full-profile pinned installation

In a fresh owned acceptance Host directory, write HanlinSDK.lock.json with revision=FINAL_SDK_SHA and all 44 public product names from that exact commit's canonical unified-package-manifest.json. Use the existing SDK installer:

    python3 Scripts/SDK/install.py --host-root FULL_PROFILE_HOST --source-cache CANONICAL_HANLIN_OBJECT_SOURCE --cache OWNED_SHARED_NATIVE_CACHE
    python3 Scripts/SDK/install.py --host-root FULL_PROFILE_HOST --check
    python3 FULL_PROFILE_HOST/Vendor/HanlinSDK/Scripts/SDK/native_artifacts.py verify-source --root FULL_PROFILE_HOST/Vendor/HanlinSDK --catalog FULL_PROFILE_HOST/Vendor/HanlinSDK/docs/native-artifacts.json

Retain real receipts, complete selected source inventory, generated manifest hashes, all 14 managed framework entries and four support mappings. Widget/Application selection must retain the canonical HanlinAppIntents projection; full application selection retains the original 507 Swift files and resource/API wiring. Installation is not a replacement for Apple host acceptance.

## 5. Existing Host adoption

After the final source is fixed, update each existing lock in its prepared isolated descendant, preserving selected products. Maktabah's existing Vendor/HanlinSDK Gitlink must equal the lock before wrapper verification. Preserve original source-policy bindings and record new Host commits.

Maktabah, base 06613ff:

    python3 Scripts/CI/prepare-hanlin-sdk.py --sha FINAL_SDK_SHA --source-cache CANONICAL_HANLIN_OBJECT_SOURCE --output OWNED_INSTALL_RECEIPT
    python3 Scripts/CI/prepare-hanlin-sdk.py --sha FINAL_SDK_SHA --verify-only --output OWNED_CHECK_RECEIPT

Lorvex, base 575a4322:

    python3 apps/apple/script/install_hanlin_sdk.py --source-cache CANONICAL_HANLIN_OBJECT_SOURCE
    python3 apps/apple/script/install_hanlin_sdk.py --check

Canonical Anytype, base 988f4519, destination Dependencies/Hanlin:

    python3 Tools/Hanlin/prepare_sdk.py --source CANONICAL_HANLIN_OBJECT_SOURCE
    python3 Tools/Hanlin/prepare_sdk.py --check

These three source-only profiles select no managed Native archives, but still require actual final-pin install/check. Historical evidence retains its original SDK d49/0dae/32da identities. New AgentCore/ChatCore, catalog or Host changes need a focused impact decision. Independent Anytype's 116cc three-package lineage does not automatically qualify the final unified profile.

Lorvex origin is boyugou/lorvex. Future authorized publication uses the verified davidpovarsky/lorvex fork URL, not origin or changed global configuration. No publication, full-profile install or Host pin adoption command was executed in this packet.
