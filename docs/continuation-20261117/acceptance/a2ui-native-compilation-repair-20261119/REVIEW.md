# Original native test compilation repair

The actual unit run44456578432 at37a246f4 failed before tests. Its native log contains three A2UI member lookup diagnostics and two Swift Testing macro throwing-call diagnostics. This packet changes two original test files only and remains unapplied.

## A2UI source proof

The resolved package pin is official a2ui-project/a2ui at3ed9601862ecc78027e20ac80ad8b1b98a5d9079. The original SurfaceViewModel declaration has public let componentsModel: SurfaceComponentsModel; it has no components member. The original SurfaceComponentsModel declaration has public var components: [String: ComponentModel] and get(_:) reads the same dictionary. Both original complete source blobs and their Git/SHA-256 records are retained. The three test expressions now read componentsModel.components; root-presence and exact component-count assertions are identical.

## Credential macro errors

The actual Apple expansion of try #require(store.load()) contains an inner closure calling $0.load() without try. The same occurs for keychain.resolve. The patch supplies try inside each macro argument, preserving the outer try for the failed requirement. Two newer phase2 direct fixture.credentials.resolve calls have the same throwing-call shape and verified throws declaration, so those receive the same correction. Property-chain fetch(...).first and await-load expressions are unchanged.

## Coverage and validation

The six original benchmark selectors remain unchanged, each still exercises six configurations: 36 observations total. Original pacing, both routes, all five owners, exact payload/order/data/model identity, EOF timing, native layout, teardown, stale-event rejection, persistence/replay, draft preservation, resource measurements and fixtures are unchanged. The matrix/fixture tail is byte-identical; no test or assertion is removed.

Both complete proposed files parse with installed Swift6.3.3; git apply --check and whitespace checks pass. This is syntax/source API verification only. A bounded portable Swift Testing typecheck was attempted and is BLOCKED because this installed Windows toolchain has no Testing module; both original and corrected diagnostic snippets/logs are retained, and no pass is claimed. Native Xcode compilation and all original assertions remain pending. No source API shim, dependency change, test exclusion or fallback is introduced.

The native unit target compiles these source files even when exact test selection names only provider tests; therefore the defect blocks the queued unit/paired builds at older source. Root owns replacement decisions and all dispatch/cancellation. Keep the failed37a evidence; use these unchanged selectors in the corrected native build.
