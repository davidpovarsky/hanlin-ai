# Bounded current-product Git context queries

Original run https://github.com/davidpovarsky/hanlin-ai/actions/runs/45292517683, attempt1/source a051e6a2076db8f0783f8c1a62fd6470e21b3d71, built and sealed the actual products, then failed before test execution. Fresh admission timed out on git rev-parse HEAD after30seconds. The calendar privacy helper and every26unit+11UI invocation were NOT_RUN.

The repair changes only the two existing Git queries inside build_context: rev-parse HEAD and the original binary tracked diff. Their bound becomes120seconds and each records command, configured bound, monotonic elapsed time and outcome to stderr. The command runs once; timeout/nonzero exceptions propagate into the original failure path. No cached HEAD, environment-only source substitute, simulator retry or product assertion/deadline change is introduced. Xcode selection remains at its original30second bound.

Exact inverse source review proves all other helper bytes unchanged. One affected existing real-Git/provenance control passed; it verifies actual HEAD, tracked changes and build context rather than merely checking a timeout literal. All unchanged controls remain retained; no Apple/native test ran for this edit. This finite preparation change does not prove host resource pressure was the cause and does not claim native acceptance.
