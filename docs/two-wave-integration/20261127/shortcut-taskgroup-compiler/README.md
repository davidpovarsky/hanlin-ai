# Concurrent Shortcut test compiler candidate

Source commit: 1ba29c65c607f813be9acb0ac4de3707ae18d210
Base: 602b29e303a633155fe07583e9ece28fce0ba113

Original run45977169204/job140431693195 failed during HanlinMiniApps build-for-testing on source466c6187. The complete original job log and MiniBuild log are retained losslessly in the adjacent archive, with explicit gzip encoding records and original byte hashes. The only actual compiler error was NativeScriptShortcutConcurrencyTests.swift:46:13: failed to produce diagnostic for expression. No acceptance test executed in that failed run.

The candidate gives the first structured TaskGroup, its child operation and result collection concrete types. The same three child operations are submitted before awaiting observed starts. The reverse release/next acknowledgement loop is preserved. The same per-nonce Probe results now leave the group as its typed return value instead of mutating an outer captured dictionary. All110 standalone XCTest assertion lines and131 XCT call-line expressions remain identical; all five method declarations and all bytes following the first group remain unchanged, including cancellation, deadline, duplicate delivery, stale-generation checks and the authored JavaScript fixture.

Root independently approved the exact source patch. The installed AppleSwift6.4 SDK signatures support the declared types/isolation/sending contracts; this read-only lookup is not a successful compile. No synthetic tests or native jobs were run by this lane. The underlying compiler solver cause is not asserted from its opaque diagnostic.

The change is confined to the MiniApps test target. Its delta has zero intersection with the actual retained392 SDK input paths, and the HanlinPlatform package tree is unchanged. This does not blanket-qualify the older Host archive across other source changes. The six OS requests already dispatched at602 retain their own source and results: their existing MiniApps plain build and separate AI_HLY test scheme do not depend on the failing MiniApps test target.

The archive includes authenticated artifact metadata and bounded HTTP range retrieval evidence for the exact diagnostic members. It does not claim verification of the entire335MB GitHub ZIP digest. Each extracted member was verified against its ZIP local header/name/length and CRC32. The original native gate remains required.
