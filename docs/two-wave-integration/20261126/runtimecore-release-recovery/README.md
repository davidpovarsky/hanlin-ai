# Exact RuntimeCore artifact recovery

The original full-Hanlin CI run45871800987/job140089266632 stopped before application compilation. Its original RuntimeCore preparation validated native input identity, then the empty artifact-run input selected a missing release. The complete failure log is retained.

## Current diagnosis

The required **artifactDependencyHash** is2ac91db28c0bee53ae53afae8e30a934e7a23d5c706cc321f7c91cbc68523194. The d1e91c identity printed immediately before failure is **nativeInputSHA256**, a separate field. The original producer run42926628418 remains successful at4784dd99c3e5892ef726e7a3cce6587eb7847997, but its artifact retention expired on2026-11-25. Fresh authenticated metadata has no artifact. The original validate_source correctly rejects this route; passing the historical run ID again would not fix the failure.

The exact original archive survives under /mnt/development/projects/hanlin-sdk-artifacts-20261123/frozen-runtime. Fresh SHA verification gives196a35562a31229b1bcf05afbe49f76470ced90a7fbf0494ecebd5c06d07440f for86,253,335 bytes. All four original release assets remain there: the unchanged ZIP, runtime-bundle.sha256, node-xcframework.sha256 and runtime-bundle/RuntimeProvenance.json. The retained provenance is byte-identical to the ZIP member.

The original verify_archive function and original checksum command pass. Required payload paths, source-patch identity and existing embedded smoke fields match the current lock. This is transport recovery of an already produced artifact; it is not a new native build, smoke execution or application acceptance.

## Concrete remedy for the publication owner

Publish the currently absent original runtime-core-v1-2ac91db28c0bee53ae53afae8e30a934e7a23d5c706cc321f7c91cbc68523194 release with those four exact existing assets, explicitly targeting producer source4784dd99c3e5892ef726e7a3cce6587eb7847997. Do not replace an existing immutable asset if publication races another owner. The original current and historical producer workflow both define these four assets.

After publication, retrieve the release assets and recheck the exact ZIP checksum, provenance and required asset inventory. Leave runtime_bundle_artifact_run_id empty so the existing original prepare-runtime-core.sh release branch consumes the restored publication. Its native-input, archive, payload, provenance and embedded-smoke checks remain mandatory and unchanged. A rerun of the original90-case CI remains open until the real producer/consumer steps and native tests finish.

Publication and CI dispatch are owned by the root coordinator and were not performed by this diagnostic lane. No runtime archive was repacked, no source or workflow was edited, and no new native job was started.

## Publication and independent readback completed

On2026-11-26 the root coordinator restored the original immutable release, explicitly targeting4784dd99c3e5892ef726e7a3cce6587eb7847997. All four original assets were uploaded unchanged, downloaded anew and checked against their retained byte lengths and SHA256 values. The original shasum command passed; the tag ref resolves to the exact producer source. A second independent GitHub API read returned release459793366, non-draft, with all four matching server digests. The historical runtime release was not promoted to the latest application release.

See publication-readback.json. This completes artifact transport recovery. The final integrated-source90 native CI and application acceptance remain separate pending gates; no new runtime production, native smoke or app acceptance is inferred from publication.
