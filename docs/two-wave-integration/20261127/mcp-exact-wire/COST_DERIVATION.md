# MCP exact wire comparison: finite resource derivation

Base source: `95c12227097f73d5755a6ff20ced43c9e2691c45`.

This candidate changes only the comparison of an already-owned MCP argument document
with the actual MCP SDK projection. The original `RuntimeAutonomyV3Tests` acceptance
constructs 800,000 copies of `שלום 😀\n`, calls a real embedded MCP server, and checks
the original renderer and stored result. Its complete source, input, assertions, and
two-minute ceiling are unchanged. This document is source reasoning, not a native PASS.

## Preserved boundaries

The complete old `HanlinHostSchemaValidation.swift` is recovered by removing one
additive block. In particular, `parse`, `requireSameValue`, schema compilation,
validation, consent identity extraction, provider schema publication, and the existing
metadata-removal policy are byte-identical. Only `MCPClientSession.checkedArguments`
calls the new `requireSameMCPWireValue` method. Its MCP.Value decoding, object-kind
requirement, actual wire projection, transport, request ownership and cancellation
remain unchanged. The new method accepts no metadata-removal parameter.

The pinned Swift-JSON tree remains `708bdb044c16fb962411560c704c0fd5434a3288`.
No vendor source, manifest, dependency pin or package declaration changes.

## Inputs and independent ledgers

Let `N0` and `N1` be the actual `Data.count` values for the original encoded document
and its already-encoded projection. They include punctuation, whitespace and escape
spelling. Counts are converted with `UInt64(exactly:)`; negative/unrepresentable
counts fail. Every sum and product uses reporting-overflow arithmetic and fails on
overflow. There is no saturation, unlimited mode or fixed cap increase.

Both parse policies and the comparison policy are constructed and validated before
the first parse. Each of the three public pinned calls owns its own finite ledger.
This candidate does not describe those independent calls as one shared meter.

For each parser, with encoded length `N`, only five of the 49 metrics change:

| Metric | Finite ceiling | Reason |
| --- | --- | --- |
| inputBytes | N | Exactly the already-owned encoded document is admitted. |
| stringBytes | N | One decoded UTF-8 string cannot exceed its full encoded document. |
| aggregateTextBytes | N | All decoded strings and keys together fit within encoded bytes. |
| retainedBytes | 16,777,216 + 3N | Existing structural allowance plus input copy, decoded text and transient string copy. |
| workUnits | 8,000,000 + 6N | Existing residual allowance plus the six byte-linear operations below. |

All other 44 fields, including depth 64, nodes 100,000, object members 20,000,
array items 100,000, key bytes 16,384, number digits 1,024, number token bytes 2,048,
absolute exponent 100,000, numeric work 250,000 and cancellation quantum 1,024,
remain the original host policy.

For comparison, `S = checked(N0 + N1)`. Only three fields change:

| Metric | Finite ceiling | Reason |
| --- | --- | --- |
| stringBytes | max(N0, N1) | A scalar string comes from one admitted document. |
| aggregateTextBytes | S | The comparator admits BOTH values using one comparison ledger. |
| workUnits | 8,000,000 + 2S | Both admissions plus exact string/key traversal. |

The comparator's original 16 MiB logical retention, structural/numeric limits and
all other 46 fields remain unchanged. Its value admission uses `owned: false`;
the comparison traverses existing JSON values without creating another owned text copy.

Each resulting `JSONLimits` calls the pinned `validate()`, checking all 49 fields.
Addressable capacities must remain strictly below `Int.max`; cumulative ledgers must
remain below `UInt64.max`. The new controls exercise the last representable retention
boundary without allocating a corresponding document.

## Source-linked cost accounting

All paths below are relative to `Packages/HanlinAgentSDK/Vendor/Swift-JSON/Sources/JSON`.
Exact file hashes are retained in `pinned-source-costs.json`.

| Source | Actual operation relevant to this allowance |
| --- | --- |
| Codec/JSONParser.swift: copyAndParse | Copies and charges every input byte once, retaining the owned input copy. |
| Codec/JSONTokenMachine.swift: next | Charges each scanned byte; number-delimiter reprocessing remains in the original bounded structural/numeric allowance. |
| Codec/JSONLexer.swift: append, scalar, closing-string branch | Retains decoded bytes; escape output charges byte work; the closing-string copy charges and temporarily retains decoded bytes before releasing the lexer buffer. |
| Codec/JSONTokenMachine.swift: accept and JSONValueAssembler.consume | Constructs the two exact key fingerprints, each via JSONKey's metered UTF-8 loop. |
| Value/JSONKey.swift: metered initializer | One work unit per fingerprint byte; matching still verifies exact scalar bytes. |
| Value/JSONExactKeyIndex.swift | Probing, collisions, growth and slot reservations remain metered. They are not granted unbounded work by this policy. |
| Value/JSONComparison.swift: JSONAdmission.value/text | Both admitted values charge their own strings/keys into the same aggregate-text ledger. Admission of these existing values does not retain another text copy. |
| Value/JSONComparison.swift: equals/textEquals; Value/JSONObject.swift: lookup | Exact string comparisons plus one lookup fingerprint and exact matching key traversal. Linear byte work fits within the two-document 2S allowance; collision and structural overhead retain the original finite residual quota. |

The parse factor six accounts for input copy, scanning, closing-string copy, escaped
scalar output, and two key fingerprints. They cannot all attain N simultaneously;
six is a conservative sum of their individual byte ceilings. The retention factor
three similarly bounds the input/text/transient-copy contributions. Existing node,
slot, traversal-frame and numeric scratch charges still compete for finite retention
and work. This policy does not promise to accept every adversarial shape of size N:
excess structural, collision or numeric cost may still fail closed.

Across the three separate successful operations, the sum of their declared work
ceilings is `24,000,000 + 8(N0 + N1)`. A conservative sum of logical retention ceilings
is `50,331,648 + 3(N0 + N1)`. These are algebraic bounds on the three finite ledgers,
not a single UInt64 accumulator, an RSS guarantee or a bound on Foundation/MCP's
already-owned data, dictionaries or encoding work. Each ledger is checked separately;
no unchecked machine addition of these displayed totals occurs in product code.

Cancellation is checked at entry, between the three operations and before return.
The original pinned parser/comparator retain their existing bounded cancellation checks.

## Validation and native admission

Portable checks only verify source inverses, exact pinned-source identities, arithmetic
boundaries and metric classification. They do not execute or substitute for Swift.

The new suite contains 11 methods, including the original >8 MiB UTF-8 shape, a tail
mutation, exact decimal/scalar fidelity, complete metadata, malformed UTF-8 and decoded
duplicate keys, unchanged depth/key/numeric limits, cancellation, old 1 MiB admission,
all 49 metric fields and arithmetic boundaries. The two large methods each retain a
two-minute native ceiling. They use the actual public comparison and pinned parser.

After root integration, the Mac owner should retain the complete outcome of:

```sh
swift test --package-path Packages/HanlinAgentSDK --filter HostMCPWireComparisonTests
```

The package requires its existing pinned dependencies and supported macOS toolchain.
Then the unchanged original app-hosted
`RuntimeAutonomyV3Tests.actualMCPTransportPreservesLargeStructuredResultsThroughTheOriginalRendererAndStore`
must pass its real MCP/renderer/store gate. Native budget sufficiency, compiler
acceptance and the original runtime acceptance are **NOT_RUN** at this source checkpoint.
