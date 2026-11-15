# Original Markdown consumer closure verification

The original six CodeBlockRendererTests/CodeBlockConfigTests genuinely passed in
[43255693521](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43255693521) at app
b667a281b793010a33ddb07860267a8eb2860afa and frozen renderer
f59bd0d533b6d94e01408bf6bdf9f5b09db57891. Its downloaded artifact13961961091 digest
`8e80e7314c27a3e7beeebc43cb875a97a78e390d52b6eba3e81a372927985d8e`, raw xcresult,
six unique Passed identities and actual package-resolution log were authenticated.
The immutable renderer checkout lock matches that log: cmark0.8.0/924936d0 and
SwiftSyntax600.0.1/0687f719, SwiftMarkdown0.7.3 and the original other dependencies.
The old recipe did not separately retain the runtime lock; this limit is preserved in
`evidence/markdown-original-43255693521.json`.

The actual app resolution [43761037885](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43761037885)
atc1a539774072b70047f128b5fde89d155fe7d986 has raw lock SHA256
`c71ab78897eb3c84f245f5efa96c5371b61172f712b8ff534bec7a9d19982fb6`. Its actual downloaded
artifact14180119013 digest `d245f3e04099528f99286784a244f417b78fb47c5665a061dce49954997abb53`
was independently authenticated. That lock admits cmark0.9.0/08ddb528923cc1a6527e02b7a1aee9e516ca749a
and SwiftSyntax603.0.2/79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1. The old checked-in app
lock's cmark0.6 was stale; it was never the actual parser of the original six-case proof.

Reuse is invalidated by the two real transitive changes. Current consumer status is NOT_RUN
until six exact methods execute with the actual app runtime states. No renderer source change,
full-app/engine build or repeated A2UI6+1/AST9 is required for this affected consumer check.

The existing manual `markdown_renderer_validation_only` dispatch/reusable workflow is retained.
`prepare_markdown_consumer_closure.py` verifies the fresh frozen renderer checkout, archives
its unmodified source/manifest/tree, then seeds ONLY its isolated test Package.resolved from
the authenticated app runtime-pin projection. Original test-only dependencies remain frozen.
No app lock, renderer manifest/source or upstream pin-source/pruning policy is altered.
Original SwiftPM must resolve the unmodified manifests and all10 exact states are checked
before compilation and after testing; incompatibility/drift fails instead of silently using
the old parser or macro. Actual checkout revisions, raw lock and source/test hashes are kept.

The cache key uses toolchain/selected consumer lock/manifest and saves only on a miss. Native
preflight records actual Xcode/Swift/SDK/OS/runtime/device. Only the six original methods run,
and strict result validation rejects missing/duplicate/foreign/nonpassing nodes. Final raw
results are archived after the owned operation exits and readable-result verification;
small logs survive separately. Phase durations are measured, not assumed cache savings.
Five portable positive/negative closure controls passed, including rejection of an old actual
checkout even when the supplied lock claims the new state; this is not a native test pass.
