# Bind the complete original manifest authority set

The integration audit on source 01d08ed453040d74a76211e7fb51a611b0d1e2cc failed because the manifest mapper still required two provenance records after the original validator began delegating domain syntax to ScriptWidgetFetchPolicy.isValidDomainDeclaration. The generator already correctly included that original helper source as its third authority. The original root failure is retained, rather than rerunning the full audit.

The mapper now registers ScriptWidgetRuntimeFetch.swift explicitly and requires exactly the metadata, package reader, and network-policy paths. Exact cardinality and set checks precede per-source SHA-256 checks. Any missing, extra, duplicate, substituted, or modified-hash authority fails. The network helper also receives a line/hash anchor in the widget family. No runtime, generator semantics, public package policy, or generated output was modified.

Only the existing manifest-contracts.test.mjs source-level case was executed: 1 passed, 0 failed, 0 skipped. It confirms the current three genuine sources, all 334 mapped fields, five new provenance mutation rejections, and the existing field/schema drift checks. This is no claim of native acceptance. The root agent owns the single combined inventory/reference regeneration after integration.

Independent read-only review by entrypoints found no concrete blocker; it is bound to the exact mapper and test hashes in independent-review.json.
