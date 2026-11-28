# Actual SDK9 binding in both built consumers

The actual completed MiniApps and AI consumer builds contain the same verified SDK9 Host archive. This is a later observation than the prepared snapshot; the earlier raw paused state remains unchanged.

| Actual completed consumer | Command-report duration | Matching resource copies |
|---|---:|---:|
| HanlinMiniApps.app | 257.921652 seconds | 1 |
| AI_Hanlin.app | 204.061476 seconds | 4 |

Both build-command records report completed / exit0 on execution source `1812bff50571c9907d15cd8b4bfbe4874be24756`. The native owner's observation began at **2026-11-25 01:25:41.261370 UTC**; its last product observation is **01:25:42.074009 UTC**. The exact retained owner receipt is 4,707 bytes, SHA-256 `988371ef49cb5f0d7ea474b245df4ade7a97f92c9660a752144631f4d2de6356`.

| Bound identity | Value |
|---|---|
| Each Host resource ZIP | 81,813,684 bytes |
| Archive SHA-256 | `3c94ebea1e314c280031ac475e2d42b63ebcf2dc2eb32d2c6e31905e3eda3240` |
| Authoring module SHA-256 | `fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9` |
| SDK manifest SHA-256 | `6fbba77d588e292b291864f0cae9e5eb5d602a4e2f208379ce1c331dedf412c9` |
| SDK input SHA-256 | `4904d0a46e4c653587fa1503a059834e9b6f35eac821a286d5eb9e96b8a92011` |

Each of the five owner-observed archive, module and manifest hashes matches the already-sealed SDK9 proof. The identical manifest binds every copy to the same SDK input identity. Exact built app/framework/test-resource paths and actual build-command identities are retained in `binding-verification.json` and the unchanged raw receipt.

This verifier made no Mac query, compiler/test invocation, archive copy/repack or repeated archive audit. It compared the small actual receipt to the existing verified SDK9 receipt. Builds and resource identity are separate from application runtime acceptance. The owner receipt records the original 52-case run as NOT_RUN at this dated observation; focused UI outcomes belong to their own actual result evidence. No Asana task closure is inferred.
