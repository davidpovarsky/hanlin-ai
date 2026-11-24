# Authenticated foreground53 reuse for original paired acceptance

Status: PREPARED_VALIDATED. The original 53-case native result is verified. Current native environment admission and the three paired UI cases remain NOT_RUN until the existing workflow executes.

Origin: https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133337462 at 6772dce6304fc6761a2200314f7d2020dc782e47. Artifact 14803354012 has 18,239,253 bytes and SHA256 83ecd7184113a12e058b5211637105ef10ec151abd0e9058686af90df567ca50. The already-downloaded archive was checked against the live GitHub artifact digest/size and passed ZIP CRC. Its actual raw foreground JSON proves 53 distinct passes. No foreground Swift suite was rerun.

The existing restore_host_proof.py now also supports an optional foreground_proof_run_id for paired acceptance. It admits only the original completed same-repository workflow with successful actual-Mac preflight and foreground execution steps, its unique live artifact, unchanged 35 source/test files and two runner/provenance files, complete original native trace, compile/link/execute lineage, raw results and checksums, and matching current Mac OS, architecture, Xcode build, Swift version and recorded compiler files. Missing, changed, inconsistent or expired evidence sets foreground_reused=false and preserves the original actual foreground execution step. Empty/default input preserves existing behavior. No iOS binary is reused by this guard.

The original receipt records /usr/bin/swiftc, the selected Swift version, verbose compiler output and Xcode build. It does not contain a separate hash for Xcode's resolved swift-frontend binary; this change does not claim one. It checks exactly the authentic recorded compiler/toolchain evidence and does not invent a stronger historic receipt.

The original Host restoration function is unchanged. After removing the two optional input declarations, one paired-only environment variable, one descriptive step name and one foreground condition, the parsed workflow is identical. Both shipping products retain their normal current-source incremental Xcode builds and the original paired test runner/selectors.

## Validation

- Actual authenticated original archive and complete raw proof: PASS under the verifier using the original recorded environment as offline input.
- 18 focused controls: PASS. They exercise the authentic original result and reject changed source, missing source, changed/missing runner, environment/compiler/version/source mismatch, raw corruption, rehashed incomplete results, failed native command, mismatched executed binary, inconsistent canonical dependency lineage, duplicate members and missing trace. They also verify failed/default admission leaves the actual foreground suite enabled.
- Python compilation and workflow YAML parse/structural preservation: PASS.
- Current native Mac environment comparison: NOT_RUN here; performed inside the original native workflow before reuse can be emitted.
- Native foreground53 rerun: NOT_RUN (the original proof is reused only after admission).
- Original cross-product paired3: NOT_RUN and held until parent full-app compilation passes.

The previously uncommitted raw text members retained here are byte-for-byte copies from the authenticated original artifact. Their original manifest, report and canonical/binary provenance remain in ../miniapps-native-45133337462. This makes the focused verifier tests reproducible without downloading or rerunning native tests.

Prepared future dispatch keeps paired_product_acceptance=true, paired_test_scope=cross_product, runtime_bundle_artifact_run_id=42926628418 and host_proof_run_id=44351078724; adds foreground_proof_run_id=45133337462. No paired dispatch has been performed by this change.
