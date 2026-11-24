# Native artifact publication and exact readback handoff

Status: awaiting a successful original Apple producer. No native asset publication has been claimed.

## Ownership and source boundary

The root agent owns the original Apple producer and workflow dispatch. The native distribution lane owns the exporter, the prepared-artifact publisher, and public catalog readback. Publication does not compile runtimes or rerun application tests.

The reviewed workflow is .github/workflows/publish-sdk-native-artifacts.yml at canonical SDK commit b66aa5e0e979f36d1a34b85e08899449b72d1dc2. The actual producer must include the export steps integrated in that commit. Failed run 45102843357 at f120d0fe1b5c0fe874df83e8d4006e79488928a0 predates these steps and is not a valid prepared-artifact producer.

## Producer receipt required before publication

1. The original Apple producer must finish with status=completed and conclusion=success in davidpovarsky/hanlin-ai.
2. The run must retain hanlin-sdk-native-prepared. The workflow has one export owner: the simulator job when selected, otherwise the device job.
3. Its catalog must bind sourceCommit to the producer head, have scope=full, no missingTargets, all 14 original native targets, and all 4 required host support groups.
4. The existing exporter verifies the prepared native slices and the original host archive; the publisher checks every recorded source input against the exact producer checkout. The exported original prepared content is reused, not reconstructed from upstream raw releases.

Required binaries: ReactNativeHeaders, React, ReactNativeDependencies, hermesvm, ExpoModulesJSI, ExpoModulesCore, ExpoModulesWorklets, ExpoUI, ExpoBrownfield, Libffi, TNSWidgets, NSCWinterTC, NodeMobile, Python.

Required support groups: HanlinExpoHeaderSupport, HanlinNativeScriptHostSupport, HanlinNodeHostSupport, HanlinPythonHostSupport.

## One publisher run after producer success

Dispatch the existing workflow from the reviewed integration ref, using the completed producer ID:

    gh workflow run publish-sdk-native-artifacts.yml \
      --repo davidpovarsky/hanlin-ai \
      --ref "$PUBLISHER_REF" \
      --raw-field prepared_run_id="$PREPARED_RUN_ID" \
      --raw-field artifact_name=hanlin-sdk-native-prepared

PUBLISHER_REF and PREPARED_RUN_ID must be actual verified values from the root lane. The publisher rejects unfinished, failed, or foreign-repository producers and checks out the exact producer head. Do not invoke it from inside an unfinished producer.

The existing job downloads the prepared artifact on a GitHub runner, verifies ZIP and source checksums, creates the immutable sdk-native-v1-<content SHA256> release, and uploads existing original archives. It independently downloads each public archive URL without authentication and checks size and SHA256 before setting the catalog to published. Existing differing release assets are rejected; they are never overwritten. It uploads native-artifacts.json to the release and retains the small hanlin-sdk-native-published-catalog artifact.

## Oracle readback without duplicate native downloads

Use the already recorded successful publisher run, without starting another native test:

1. Read its final run/job metadata and its exact producer input; save the producer SHA and publisher SHA.
2. Download only hanlin-sdk-native-published-catalog, not the prepared native ZIP artifact.
3. Verify the catalog is published, is full scope, contains exactly 14 binary targets and 4 support groups, has no missing targets, and its source inputs match the producer checkout.
4. Read the exact content-addressed release metadata. Confirm every expected archive name, byte count, canonical release URL and API SHA256 digest against the catalog. The full public archive readback is already performed by the successful publisher; retain that source-bound result instead of downloading the archives again on Oracle.
5. Fetch the small public native-artifacts.json anonymously and compare its exact bytes/SHA256 to the retained published catalog. Confirm the release contains that same catalog asset.
6. Commit the actual published catalog to docs/native-artifacts.json together with a receipt containing the producer and publisher run URLs, release URL, catalog SHA256, exact asset digest/size mapping and limitations. Do not invent download URLs before publication.

If a release API response has no digest, that absence does not establish a checksum match. Retain the publisher's exact public archive readback evidence, and investigate the missing metadata without silently weakening the immutable-asset guard.

## Consumer integration boundary

The root manifest owner decides when to use the verified URL/checksum declarations in the default package. Selected-product installer profiles remain necessary: measured SwiftPM behavior materializes declared binary targets even for a source-only selected product. The canonical installer prunes the exact target/dependency closure before resolution, so engine, Composer and rich-UI consumers can remain free of unrelated native artifacts.

Installed full/native profiles use the verified local prepared paths and original shared host staging commands. Avoid downloading a second set of URL binary targets after the same artifacts were installed locally. NativeScript metadata and Python host resources remain original required build integration; publication alone does not establish app launch, calendar runtime or visual acceptance.

## Current evidence

The source/export wiring, bundle guards and packaging tests are recorded beside this file. The actual full publication and readback remain pending the successful producer. The failed pre-export run is classified separately under ../native-run-45102843357/; no result from it is reused as a native runtime or UI pass.
