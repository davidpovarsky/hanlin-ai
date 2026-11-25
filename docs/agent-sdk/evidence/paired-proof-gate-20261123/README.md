# Required paired proof reuse stops on mismatch

Base: `0b40a021c6d28e4d1c47ed87060d063c8456ba9f`.

The original paired route may reuse authenticated Host and foreground proofs. Its default behavior previously returned success after writing INVALIDATED, allowing the workflow to execute prerequisite suites again. This requested continuation must diagnose a mismatch before replaying those accepted suites.

The workflow now sets `PAIRED_PROOF_REUSE_REQUIRED` only when paired acceptance and both explicit origin IDs are selected. After the existing helper writes both original admission receipts, it exits nonzero unless both proofs passed. The normal default workflow behavior is preserved. Every checksum, source-closure, toolchain, native result and archive predicate is byte-identical; no suite, product source, UI test, timing, or assertion changes.

## Verification

- **PASS**: 21 focused portable controls. New controls exercise actual subprocess failure for Host and foreground mismatches separately, verify both original receipts survive, and verify no following command executes. A complete required pair proceeds; optional reuse preserves existing behavior.
- **PASS**: authentic foreground artifact14803354012 from [45133337462](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133337462), SHA256 `83ecd7184113a12e058b5211637105ef10ec151abd0e9058686af90df567ca50`, 18,239,253 bytes. Original53 executed cases, complete raw lineage, all35 current sources/tests and both runner inputs match.
- **PASS**: authentic Host artifact14454531510 from [44351078724](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44351078724), SHA256 `8ebe0c0ec78b94ce960206551f474205a091cf8dabf24432a12773496aaa328d`, 58,049,831 bytes. Original focused7/7 and broad152/153 with1skip are retained. All139 Host/test/fixture/build input files match the original source. Existing archive validation confirms actual packed dependencies and current source modules.
- **PASS**: original paired runner and all three cross-product case bodies remain byte-identical to6772dce6; workflow is unchanged except the single admission-mode environment value.
- **NOT_RUN**: actual new Mac OS/Swift driver/Node fingerprint admission and the original paired3 UI cases. Portable source validation does not establish native environment equality. The existing native guards must pass before any paired work proceeds.

## Frozen continuation plan

Use the existing `validate-app-split.yml` route from this reviewed base plus this infrastructure-only change: paired_product_acceptance=true; paired_test_scope=cross_product; runtime_bundle_artifact_run_id=42926628418; host_proof_run_id=44351078724; foreground_proof_run_id=45133337462. Registration, signing and release-resource audit inputs remain false. Preserve ordinary current-source builds of both products and original request/return, cancellation and transfer/rollback cases. No baseline suite is replayed when the required proof admission fails.
