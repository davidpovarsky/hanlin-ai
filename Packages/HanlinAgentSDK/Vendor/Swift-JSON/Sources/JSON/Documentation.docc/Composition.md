# Compose native operations

Run synchronous native operations and explicitly instrumented adapter work with
one finite ledger. The experimental composition facade does not meter arbitrary
callback instructions, allocator sizes, physical RSS, or Foundation instructions.

```swift
import Foundation
import JSON
import JSONSchema

let report = try JSON.withComposition { (scope: borrowing JSONCompositionScope) in
    let document = try scope.parseDocument(Data(#"{"count":9007199254740993}"#.utf8))
    try scope.reserveExternalLogicalBytes(64) // Adapter-declared output frame weight.
    try scope.chargeExternalWork(1)           // Before the adapter's corresponding work.
    let pointer = try scope.pointer(tokens: ["count"])
    _ = try scope.uri("https://example.invalid/schema.json")
    return try scope.resolve(pointer, in: document.root)
}
```

The scope is borrowed, noncopyable, synchronous and not Sendable. Its methods
mutate invocation-owned private state. The closure cannot replace or swap the
borrowed facade. It has no public
initializer, continuation, refund or ownership token. Every reservation lasts
until completion. Re-admitting a value reserves its graph again; resolving
reserves its input graph and selected graph again. This intentionally overcounts
aliases and dead temporaries rather than assuming copy-on-write releases memory.
Reserve each external result, queue, diagnostic and copied slot before growth;
choose and audit its logical weights in the adapter. A zero reservation makes no
claim about opaque storage. External loops must charge/checkpoint regularly.

`parseDocument` pre-admits the complete Data-to-array buffer before allocation,
charges each copied byte and runs the native source-map parser on the same meter.
The original caller Data is excluded; the array copy remains conservatively
reserved alongside decoded values, source bytes, spans and final output.
Each document applies `inputBytes` independently. Completed input counts remain
in the cumulative report; work, logical retention, accepted-capacity history and
terminal health never restart. Other native capacities remain conservative across
the scope. Version 1 native weights and internal scratch releases follow the resource
contract. Reported peak is this ledger's conservative logical peak, not a sum of
independent operation peaks. Final retained bytes include all unreleased
reservations, even when the callback returns a smaller result.

Completion reserves 424 logical bytes (32 header bytes plus 49 UInt64 slots)
before allocating the independent report counter buffer. It charges 49 counter
copies plus one final aggregate-work update: 50 work units. The returned result
and all conservative reservations remain live through this final admission.
An adapter must also reserve its result containers before growth; the generic
result type does not reveal arbitrary storage to the library.

All owned helper errors are terminal, including syntax and missing-target errors.
Catching one cannot produce a successful report. Scope exit rethrows the original
owned failure ahead of any later callback error. Restriction intersects limits
and preserves admitted capacities, cumulative work, live bytes and health.
A fresh invocation has a fresh budget; nesting does not certify inner work as
part of an outer report. Use a single borrowed scope throughout the adapter.

URI operations in JSONSchema use the core domain: URI identity and adapter models
are not compiled schema plans. They do not charge compiledPlanBytes or
compileWorkUnits. This facade does not compose schema compilation or evaluation.
No circular JSON-to-JSONSchema dependency is introduced.

`JSONOperationReport` has a public initializer. Its type is not a cryptographic or
unforgeable receipt, and it cannot establish that an arbitrary callback charged
all its work. An adopting adapter must own its final accounting boundary and audit
all external work and reservations. Independent reports cannot retroactively
certify one enforced invocation.

## Borrowing and compiler qualification

The supported helper shape passes the active scope explicitly as a
`borrowing JSONCompositionScope` parameter to a normal synchronous function.
Selection and native helpers continue through that same scope and ledger; this
usage pattern does not grant an escaping continuation or a second budget.

A Swift 6.4 investigation against `c79d48c15f83ef88bed9459d9abcf05e54bd0bea`
recorded 49 follow-up compiler invocations: 22 valid compilations, 24 compiler
crashes and three intended rejections. Explicit borrowed-parameter helpers had
limited positive object-generation and public-consumer evidence. Bound-method
escape and nested functions capturing the borrowed scope could pass type checking
and then abort during IR/object emission. Xcode and Command Line Tools in that
matrix shared an Apple compiler revision; they were not independent revisions.

These observations qualify those source/toolchain shapes only. A compiler crash
is not a normal rejection, a supported escape or a universal compiler-enforced
non-escape proof. Do not infer safety from typecheck success alone. The existing
scope, terminal-failure and accounting contracts remain unchanged; runtime
invalidation alternatives and later accounting/root proposals need separate review.


## Compiler and portability boundary

Pass the borrowed scope explicitly to adapter helper functions:

```swift
func visit(_ scope: borrowing JSONCompositionScope) throws {
    try scope.chargeExternalWork(1)
}
```

Both Apple Swift 6.4.0.34.1 and Swift.org 6.4 reproduce an ownership-verifier
crash when a nested helper captures an inferred closure parameter. Explicitly
annotate `(scope: borrowing JSONCompositionScope)` as above: the nested synchronous
helper compiles, shares the original ledger, and escaping capture receives the
normal borrowed-parameter diagnostic. Ordinary calls also work through explicit
borrowed helper parameters.

Forming a bound method reference such as `scope.checkpoint` still crashes both
observed compilers, including through an explicit borrowed helper. Call the method
or a helper directly. Reduced reproducers with no JSON imports are preserved on the
historical composition qualification branch (PR #63). These are compiler defects,
not intended negative-test passes; no experimental flags or weaker ownership model
are used.
