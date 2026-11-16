# Exact values and native coding

Preserve decimal meaning, scalar keys and field presence from bytes to Swift models.

## Start with strict bytes

``JSONParser`` accepts String, Data and owned byte arrays. A successful parse
certifies exactly one root, trailing whitespace and EOF. Invalid UTF-8, duplicate
decoded keys and unpaired surrogate escapes fail rather than being repaired.

```swift
let parser = JSONParser()
let value = try parser.parse(#"{"count":9007199254740993,"note":null}"#)
let selected = try JSONPointer(parsing: "/count").resolve(in: value)
let integer = try selected.numberValue!.integer(as: Int64.self)
```

This example inspects known input. Handle an optional accessor or thrown kind
mismatch when the input's shape is unknown. ``JSONNumber`` preserves exact decimals;
``JSONNumberConversionPolicy/exact`` proves mathematical equality when converting.
Decimal 0.1 cannot pass exact binary64 conversion. Rounded conversion is explicit.

## Keep text identity and presence

``JSONKey`` distinguishes composed and decomposed scalar sequences. Ordinary Swift
String dictionaries can collapse them; native decoding rejects that projection.
``JSONObject`` iteration keeps insertion order, while equality ignores it.
Its subscript is an unmetered convenience; bounded accessors and ``JSONComparison``
charge untrusted traversal.

``JSONPresence`` separates missing, null and a non-null value. Keyed Codable
presence helpers omit absence and encode null explicitly. Normal Optional coding
retains its standard behavior. Checked object/array accumulators require exclusive
borrows and reject duplicate keys before growth. Direct enum cases and literals
are trusted construction, admitted when a bounded operation consumes them.

## Compose Codable with the codec

``JSONValueEncoder`` and ``JSONValueDecoder`` work directly on exact values.
Parser decode and writer encode conveniences share cumulative work with the codec
and intersect their configured limits. Native JSON/JSONObject/JSONNumber passthrough
preserves payloads. Foreign Codable bridges inherit the foreign coder's fidelity.

Integers require exact conversion; Float/Double decode rounds into a finite target.
Data defaults to strict Base64. Date defaults to its own Codable representation;
explicit ISO-8601 uses bounded UTC text. Caller model callbacks can discard fields
and execute arbitrary caller work; their result is not a raw-preservation guarantee.

## Observe limits without confusing them with memory measurements

``JSONOperationReport`` exposes successful versioned counts and logical retention.
Subsystem work is included in aggregate work. Capacity-only checks may report zero.
Logical bytes are distinct from allocator sizes and RSS. Reports contain no clocks
or payloads in their statistics.

Across separate calls, carry checked remaining work from successful reports and
keep subsystem ceilings independently. A failed or cancelled stage is terminal for
the composition because it has no successful report of failed work. Synchronous
APIs run on the caller executor; immutable facades can be shared and each invocation
owns its mutable context.

## Topics

- ``JSONParser``
- ``JSONNumber``
- ``JSONObject``
- ``JSONPresence``
- ``JSONValueEncoder``
- ``JSONValueDecoder``
- ``JSONOperationReport``
