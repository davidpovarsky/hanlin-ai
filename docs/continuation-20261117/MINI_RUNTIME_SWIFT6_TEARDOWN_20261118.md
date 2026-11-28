# Companion runtime UI harness Swift 6 teardown — 2026-11-18

Native run 44246642312 at 2fe24c583888c676a2b152dcf27fb4eabcc20260 stopped during test compilation, before either runtime scenario ran. Apple Swift 6 diagnosed sending XCTestCase self from the synchronous nonisolated tearDownWithError override to its MainActor-isolated capture helper. The standalone product itself did not produce a runtime assertion failure.

Failure diagnostics are now emitted directly in that override, using the same screenshot/AX attachment operations already compiled successfully in HanlinPairedProductUITests. No assumeIsolated, unsafe Sendable conformance, disabled Swift concurrency checking, weakened runtime assertion or substituted engine was introduced. Runtime assertions and the normal MainActor capture helper remain unchanged.

Original evidence: artifact 14402357586, API ZIP SHA-256 2f51785968110501022f6ff0d13cdd8abc540253bf35f9aa722e59e44f70e068; build.log SHA-256 a103e41e25e1230ee0aae22376818b9c031c2225c9beb43049fd01ba1ccbefc9; acceptance.json SHA-256 55ee5972cf654b674a91da6aecfbbec3549d2ab529e4a4ff7e368a5734d2a809. Corrected native compilation and both original standalone runtime scenarios remain required.
