# ``JSON``

Exact values and strict, bounded UTF-8 coding on macOS 27 with Swift 6.4.

``JSONNumber`` stores a sign, decimal digits and a bounded decimal exponent.
Equivalent decimal spellings compare mathematically; integers beyond binary64
precision remain distinct. ``JSONKey`` and string values compare decoded Unicode
scalars without canonical normalization. ``JSONObject`` preserves insertion order
and uses order-independent equality. A duplicate decoded key is a syntax error.

``JSONParser`` and ``JSONWriter`` share the incremental strict codec used by
JSONStreaming. Parsing requires one complete root, trailing whitespace and EOF.
The writer supports compact/pretty output, insertion/scalar key order and
preserved/normalized decimal spelling. Scalar sorting is deterministic JSON
output, not a cryptographic canonicalization standard.

``JSONValueEncoder`` and ``JSONValueDecoder`` implement native value-based
Codable. Direct JSON/JSONObject round-trips preserve raw scalar keys and numbers.
String dictionaries fail explicitly if canonical String equality would collapse
keys; CodingKey enumeration rejects changed scalar spellings. User callback errors
propagate. Integer conversion is exact; native Float/Double projections round to
the requested finite binary type. Use the exact JSONNumber conversion to prove
mathematical equality. Standalone number conversion provides exact or rounded policies. Binary floating bridges admit at most 822 bytes
using 800 significant digits plus a sticky tail, preserving binary32/binary64
rounding boundaries without opaque whole-token scans. Data/date behavior is configured through
``JSONCodingOptions``. The library does not use Foundation JSON serialization. Base64 uses metered
native loops. The explicit ISO-8601 strategy renders UTC with fractional seconds, encodes
four-digit years 0000–9999 and caps input at 128 UTF-8 bytes. External Codable
bridges inherit the external coder's key/numeric fidelity.

``JSONPointer`` implements RFC 6901, including percent-decoded URI fragments and
strict runtime array indices. ``JSONPresence`` distinguishes missing, null and a
present non-null value. Construction helpers enforce limits before insertion.
``JSONDocument`` owns its input and bounded source mapping;
``JSONPreview`` caps traversal and redacts exact keys before accessing their
payloads. Previews are diagnostic snippets and may be incomplete JSON.

## Resource and ownership policy

Every default ``JSONLimits`` profile is finite. Per-value capacities and
cumulative work quotas are inclusive; overflow and exhaustion produce a
structured ``JSONFailure``. Cancellation is checked at entry, before growth and
within bounded work intervals. Caller Codable callbacks remain caller work.

``JSONOperationReport`` exposes charged counts and peak logical retention.
Accounting version 1 uses published logical weights, not heap size, allocation
count, elapsed time or RSS. Metrics checked only as capacity predicates have no
cumulative charge and report zero. Reports are Sendable when their result is.
Immutable values/configurations are checked Sendable; mutable operation state
belongs exclusively to each invocation.

## Topics

### Guides

- <doc:ExactValuesAndCoding>
- <doc:QuickEntryPoints>
- <doc:CommandLine>
- <doc:ExactPersistence>
- <doc:Composition>

### Exact model
- ``JSON/JSON``
- ``JSONNumber``
- ``JSONKey``
- ``JSONObject``
- ``JSONMember``
- ``JSONComparison``

### Codec and native coding
- ``JSONParser``
- ``JSONWriter``
- ``JSONWritingOptions``
- ``JSONIndentationUnit``
- ``JSONValueEncoder``
- ``JSONValueDecoder``
- ``JSONCodingOptions``

### Navigation and diagnostics
- ``JSONPointer``
- ``JSONPresence``
- ``JSONDocument``
- ``JSONPreview``
- ``JSONDiagnostic``
- ``JSONFailure``

### Resource policy
- ``JSONCompositionScope``
- ``JSONLimits``
- ``JSONResourceMetric``
- ``JSONOperationStatistics``
- ``JSONOperationReport``

### Scoped reads

- <doc:ScopedReads>
- ``JSONReadCursor``
- ``JSONAccessFailure``
