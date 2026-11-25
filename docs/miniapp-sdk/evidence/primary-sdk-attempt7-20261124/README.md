# Actual attempt7 SDK and embedded Host reconciliation

Execution source: `fd81d602d3b25f09162a659e1e0cf0582e91a93a`. Original native preparation and export passed. The final authoring module is embedded in the new Host archive; all SDK source inputs and the later actual built app resources bind to the same prepared identity. Selected application cases, physical acceptance and screenshots remain separate.

## Exact identities

| Item | Actual value |
|---|---|
| Host archive | 81,813,086 bytes |
| Host archive SHA-256 | `c4e85e967f873ffbe907990c5d9d612b5b6f95871b4e85c736ec0799f09cb1af` |
| SDK manifest SHA-256 | `6a5ce216ab722741314a893f8bb226773da27c9d6151f6cbc28f46901b8fcb94` |
| Recomputed SDK input SHA-256 | `7073ff408de405da0fc2e992993588529a6271f1c41d87dea520b10fcdf62db0` |
| Authoring module SHA-256 | `aecc8c0ba732396a637a7d7eda8864f7bdc5b3acbe0894a640c5e9c2e8ac1cb9` |

All 20 transfer members and 222 SDK source inputs match actual bytes. The embedded and retained manifest are identical and the complete SDK archive member set matches its manifest. Against attempt6, four SDK inputs/members changed; 218 inputs and 25,657 member records are unchanged, including all 5,210 declarations, 29 examples and both original compiler entrypoints. Engine, upstream and installation metadata is unchanged.

All 3,102 outside-SDK Host members were compared by actual uncompressed SHA-256 in place. Only the authoring module changed; 3,101 members are identical. No archive was copied or fully extracted.

## Four generated documents

These four files total **780,842 bytes**, all mode `100644`. The canonical materialization binding is `f291a4588bcfd8a8317ed94bd97c41eab97cc4d2fdd6252214622cffeabaf753`. Full before/after hashes and exact payload selectors are in `prepared-source-delta.json`. This lane did not materialize production files.

| File | Verified difference |
|---|---|
| `MANIFEST_REFERENCE.md` | Exactly 36 shifted authoring-source line anchors; field descriptions/contracts unchanged. |
| `extension-reachability.json` | Source commit and authoring source hash; reachability matrix unchanged. |
| `extension-reachability.md` | Source commit only. |
| `source-inventory.json` | Source commit, authoring hash and 36 existing manifest source anchors/hashes; contract fields/values unchanged. |

All inventory/source-reference hashes and line bounds bind to the exact execution source. These indirect inputs explain the changed SDK identity.

## Executed original proof

All four original documentation projects passed with zero diagnostics against this new SDK and final authoring checker: Expo, NativeScript, ScriptWidget and ScriptWidget controls. The report covers 14 source fences, seven JSON fences and eight explicit non-authoring exclusions. Original per-engine checking options, snippet contexts and compiler versions are retained.

The TypeScript alias note was re-bound to all four actual archive members and the original source/lock. Package `@typescript/typescript6@6.0.2` is the original 45-byte entrypoint wrapper for the locked `typescript@6.0.3` implementation under `@typescript/old`. The manifest records both; their bytes are unchanged.

The actual full Host run reports **169 tests, 168 pass, zero fail, one existing long-duration-test skip**. All three newly added resolver cases passed. The exact log and skipped test are retained. The regression source SHA is `958d0e0a71f47fa7677e412cd1a0ed40da43feb898b182df84e63256a05e5865`; the producer includes Tests in its source fingerprint, while the archive omits Tests under the existing packaging rules. Host counts do not replace the 52 application cases.

The native catalog has all 14 required targets, no missing targets, and 16 unchanged direct source inputs. All native artifact content metadata is unchanged after release-URL substitution; only HanlinNodeHostSupport support bytes/checksum changed. No full native export was extracted.

The separate actual built-resource receipt at 22:29:29 UTC binds completed MiniApps and AI builds to five exact archive copies: MiniApps app root plus AI app/test/framework resources. Every copy matches this archive and final module. Completed builds/resource identity do not prove application cases or screenshots.

## Dated execution and limits

Actual source advance: **21:59:06.434280 UTC**. The first controller ran only the bounded original Host lifecycle/relocated-CLI prefix at 22:14:11; it passed at 22:14:19 while heavy work awaited capacity. Heavy native preparation began separately at **22:22:35.324575**, passed at **22:24:47.323201**, and export passed at **22:25:08.234358**. The immutable prepared snapshot was captured at **22:26:16.906412** with paired acceptance running. Later build/resource evidence is retained separately. Subsequent application failures or terminal results supersede that historical checkpoint without rewriting raw proof.

The inspector only reads retained output bytes and immutable Git objects. It ran no product test, compiler, generator, package manager, native tool or CI, made no Mac query, repeated no 112-member audit and modified no production source. All files in this commit are evidence.
