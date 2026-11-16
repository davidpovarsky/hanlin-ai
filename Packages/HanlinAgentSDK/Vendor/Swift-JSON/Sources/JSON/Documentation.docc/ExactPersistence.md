# Exact persistence

Transport exact JSON through a foreign Codable implementation using
``JSONCodablePayload``. The fixed Version 1 envelope carries the ASCII marker
`swift-json-value`, integer version `1` and strict standard Base64 in `utf8Base64`.
The inner strict UTF-8 document keeps decoded scalar sequences, member and array
order, exact decimal meaning and admitted numeric lexemes. Its compact writer
does not preserve source whitespace, escape spelling, labels or source maps.

Construction/opening use finite balanced limits; explicit limits can tighten
them. Automatic Codable also uses balanced limits. Native nesting shares the
enclosing cumulative meter. Foreign coder allocations and callbacks remain caller
work. Logical bytes include overlapping owned buffers and temporary DOMs, and
are distinct from process RSS. A decoded wrapper stores only validated UTF-8;
``JSONCodablePayload/value(limits:)`` performs a new complete parse.

Required missing/wrong field types use ordinary Codable errors. An unsupported
marker/version, malformed Base64 or invalid inner document produces bounded
`DecodingError.dataCorrupted`. Resource/configuration errors and cancellation
retain their types. Corruption never becomes a null value.

SwiftData belongs in an application or example target importing SwiftData.
Use `@Attribute(.codable)` for the wrapper, with an independent application schema
version. An optional attribute of `nil` differs from a present wrapper preserving
JSON null. Query and sort ordinary model fields; this example establishes no
queryability of the embedded JSON. Persist/save, release the model/context/container
and recreate the container at the same disk URL to test reopening.

Package version, payload format version, application data schema and SwiftData
model schema are separate. Version 1 has no heuristic legacy detection or silent
upgrade. Applications migrating bare JSON/Data must explicitly validate the
conversion and retain the original data according to their own migration policy.

## Topics

### Explicit wrapper

- ``JSONCodablePayload``
- ``JSONCodablePayload/preservingWithReport(_:limits:)``
- ``JSONCodablePayload/valueWithReport(limits:)``
