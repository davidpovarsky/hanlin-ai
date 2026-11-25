# ZIPFoundation alignment for the original Maktabah consumer

Status: **SOURCE ONLY / NOT QUALIFIED**. The previous qualified union is
`a11c6734eba0ce9206bf80d5e981645bfbc0c73b`; its raw Core7, canonical graph and
original C8 app05 receipts retain their exact original inputs and scope.

Maktabah and the original Anytype SDK both require exact ZIPFoundation 0.9.20
(revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`). Original HanlinPlatform
requires exact 0.9.19 (`02b6abe5f6eef7e3cbd5f247c5cc24e246efcfe0`), which prevents
one dependency graph. This checkpoint changes only that original manifest's exact
requirement to 0.9.20. AI_HLY's existing compatible >=0.9.19 requirement need not
change. Core stays `abf0921c6e89e6521cc2b510ff11016b45a0ef08` and OpenTelemetry
stays exact 2.6.0. No shared implementation, source or binary is copied.

The original canonical generator and real Apple resolver must now regenerate/check
Package.swift, the unified manifest and affected active locks. They have not run
at this checkpoint. Historical evidence locks must stay immutable. The resolver
must retain unrelated pinned revisions and validate the existing four Maktabah
local package products. Anytype's ZIP provider and final symbol-ownership gate
remain unchanged and strict; the app must not introduce a second ZIP provider.

Affected native regression plan: the six unchanged HanlinPackageCenter methods
(actual exporter/importer, staging/cleanup, NativeScript archive, File Provider
spaces, Hebrew Unicode and malformed manifests); the complete original archive
policy methods (including all four traversal parameters); and original widget
archive import/install-loader methods for their actual archive fixtures where
required by the final transitive closure. Use original products and test sources,
record exact invocations, ZIP revision, toolchain, input hashes and raw receipts.
Final original Host archive/package validation and Maktabah Live/UI remain open.

The newer independent 6f/C9 production work is not merged or credited here. It may
be reassessed after its owner's affected gates qualify; this scoped alignment
must not relabel C8 app05 as a run on changed ZIP bytes.
