# Original runtime fixture contract corrections

These changes address four specific failures from the original application test run45977172889 on466c6187. They are source corrections pending execution of the original native tests. The original failed run is retained as failed/cancelled; no result is promoted.

| Original test | Corrected fixture contract |
| --- | --- |
| CMD01 actual awk tool execution | Compare the exact user-facing stdout including its final newline. The production model-facing result deliberately also carries durable runtime-job metadata. Preserve the original direct argv/stdout and missing-file checks; additionally require exit0, stdout17bytes, stderr0, no truncation, no timeout and no cancellation. |
| PY02 distribution/import-name mismatch | Supply the pinned installer with valid SHA256 URL-safe unpadded RECORD digests and exact byte sizes for the three actual wheel payloads. The RECORD self-entry remains empty as before. Original package bytes, live loopback server, install/import assertions and deadlines are preserved. |
| Optional Node lifecycle resource | Resolve RuntimeHostResources.zip through HanlinApplicationResources.bundle, exactly as the production NodeRuntimeService does. Preserve the original archive, digest, extraction and actual lifecycle assertions. |
| Hostile ZIP compression ratio | Exercise an explicit maximumCompressionRatio100 policy against the unchanged1:1000 fixture. The production default intentionally admits full source packages; this test verifies the supported explicit ratio policy. Original rejection assertions and all other hostile archive cases are unchanged. |

All original function selectors remain. CMD01's obsolete modelText expectation and the resource-owner expression are intentionally corrected, not described as byte-identical assertions. Six stronger diagnostic expectations are added. The PY02 RECORD helper is the only added function. The large original MCP payload test, FINAL12 source fixture, all native time limits, production implementations, upstream engines and pins are unchanged.

Independent source reviews were completed for the first three corrections and the CMD01 additive change. Exact source hashes, counts, review hashes and source patch are retained here. No native build or test execution is claimed by this packet.
