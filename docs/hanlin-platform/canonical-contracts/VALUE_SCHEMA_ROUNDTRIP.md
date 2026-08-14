# Value and Schema Round-Trip Contract

Status: normative first-integration contract implemented by
`HanlinPlatformContracts`.

## 1. Domains

| Domain | Role | Canonical status |
| --- | --- | --- |
| `HanlinValue` | Rich portable domain value, including exact Int64, finite binary64, and bytes | Canonical after the encoding evolution below |
| `HanlinJSONValue` | Strict JSON-domain interchange value | New canonical type |
| `RuntimeJSONValue` | RuntimeCore host response/config value | Runtime-only |
| Foundation JSON (`JSONSerialization`, `JSONDecoder`, `NSNumber`, `[String: Any]`) | Apple implementation boundary | Adapter-only |
| MCP SDK `Value` and encoded MCP schema JSON | MCP protocol/SDK boundary | Provider-only |
| Future Scripting JavaScript values | Script-engine boundary | Provider-only; unavailable today |
| `HanlinValueSchema` | Closed schema for rich Hanlin values, including bytes | New canonical type |
| `HanlinJSONSchemaDocument` | Lossless JSON Schema document with dialect and unknown-keyword preservation | New canonical type |
| Current `HanlinJSONSchema` | Closed tagged schema currently used by manifests | Replace after cutover |

## 2. Rich value representation

The semantic `HanlinValue` cases remain:

```text
null | bool | integer(Int64) | number(binary64) | string | data(bytes) |
array([HanlinValue]) | object(HanlinObject<HanlinValue>)
```

Its canonical tagged wire representation encodes:

- integer as a canonical base-10 signed Int64 string or integer field whose
  decoder proves exact Int64 recovery;
- number as the exact 64-bit IEEE-754 bit pattern in 16 lowercase hexadecimal
  digits, rejecting exponent/locale/parser differences and preserving `-0.0`;
- data as unpadded base64url plus an explicit byte count; and
- object keys as Unicode strings with duplicate detection before canonical
  object construction.

`HanlinObject` uses the exact UTF-8 byte sequence for key equality and hashing.
This is required because Swift `String` equality otherwise treats canonically
equivalent Unicode spellings as equal even though this contract does not
normalize or rewrite keys.

The former package-only tagged encoding had no product or persisted consumer and
is not retained as a compatibility format. The canonical encoding is the only
supported package representation.

## 3. JSON-domain representation

`HanlinJSONValue` has `null`, `bool`, `integer(Int64)`, `number(binary64)`,
`string`, `array`, and `object`, but no bytes. It preserves the producer's
integer classification only when that classification is provable. A generic
Foundation `NSNumber` or SDK number that cannot be classified without ambiguity
is treated as binary64.

Canonical JSON encoding follows these rules:

- UTF-8 only; no BOM.
- Object members sorted lexicographically by the unmodified UTF-8 bytes of each
  key. Keys are not Unicode-normalized, case-folded, trimmed, or rewritten.
- Minimal required JSON escaping; `/` is not escaped.
- `true`, `false`, and `null` use lowercase literals.
- Integers use canonical base-10 with no leading zero and no `+` sign.
- Binary64 uses the shortest decimal spelling that round-trips to the identical
  finite bit pattern. When that spelling would otherwise look like an integer,
  a floating marker is retained. In particular, `0.0`, `-0.0`, `1.0`, and
  `-1.0` encode exactly as written here, so decoding preserves `.number` and
  the sign bit of zero.
- NaN and infinities are rejected before encoding.
- No insignificant whitespace.

This policy is intended to be deterministic; the exact algorithm and golden
bytes must be verified in Swift and the shipped script/runtime language before
calling the encoding canonical. It is not a claim that the current
`JSONEncoder` implementation already meets every rule.

## 4. Exact conversion rules

### 4.1 Integer versus floating point

| Conversion | Rule |
| --- | --- |
| `HanlinValue.integer` -> JSON/Foundation/MCP | Succeeds only if the destination represents the exact integer. For JavaScript/Scripting Number, require `abs(value) <= 9_007_199_254_740_991`; otherwise fail unless a future explicitly typed BigInt contract is negotiated. |
| `HanlinValue.number` -> destination number | Succeeds only for finite values and only if encode/decode returns the identical binary64 bit pattern. If the destination normalizes signed zero and signed zero matters, fail. |
| JSON integer token -> `HanlinValue` | Use `.integer` when it fits Int64. If outside Int64, fail; do not demote to Double. |
| JSON decimal/exponent token -> `HanlinValue` | Parse as binary64 only if finite and a canonical re-encode round-trips to the same binary64. Lexical spelling is not identity. |
| Foundation `NSNumber` -> canonical | Distinguish `CFBoolean` first. Accept an integer only when the source exposes an integral numeric type and exact Int64 conversion. Otherwise accept finite binary64; reject ambiguous values when source type cannot be proven. |
| `RuntimeJSONValue.number(Double)` -> canonical | If finite and mathematically integral within Int64, it still remains `.number`, because RuntimeCore already lost the producer's integer case. Never invent integer provenance. |
| MCP SDK number -> canonical | Preserve the SDK's actual integer/float distinction if one exists in the pinned source interface; otherwise treat as binary64. SDK behavior must be compiler/source verified before implementation. |

No adapter turns `1.0` into integer `1` merely because they compare
numerically. Schema validation may accept a mathematically integral number only
if the schema explicitly defines that coercion; the default is no coercion.

### 4.2 Binary data

- `HanlinValue.data` round-trips only through rich tagged Hanlin encoding or a
  typed blob attachment/handle contract.
- Conversion to plain Foundation JSON, MCP JSON arguments, JSON Schema values,
  or JavaScript JSON fails with `value_not_representable` and the value path.
- A caller may explicitly select an application schema that represents bytes as
  a base64 string. That is a schema-directed transformation producing a string,
  not an implicit value conversion.
- MCP image/audio content remains typed MCP content and maps to canonical
  attachment descriptors/handles, not to a fake JSON data value.

### 4.3 Null and absence

- `.null` is a present value and round-trips as JSON `null`.
- A missing object key, absent optional field, Swift `nil`, and `.null` are
  distinct.
- Foundation `NSNull` maps to `.null`; Swift optionals are handled by the
  containing contract, not the value converter.
- Schema `required` decides presence. Nullable values require an explicit null
  alternative; optional does not imply nullable.

### 4.4 Object keys

- Keys are arbitrary non-null Unicode strings, including the empty string, at
  the value layer. Descriptor-specific schemas may impose stricter rules.
- Input decoders must detect duplicate JSON member names before building a Swift
  dictionary. Duplicate names are an error even if values are identical.
- Keys are not Unicode-normalized, case-folded, trimmed, or path-normalized by
  the value layer. Two distinct scalar sequences remain distinct.
- Canonical encoding sorts keys deterministically but does not change them.
- Keys that cannot be represented by a destination API fail; they are never
  dropped.

### 4.5 Non-finite numbers

NaN, positive infinity, and negative infinity are invalid at every canonical
boundary, including schema bounds/defaults/enumerations, Foundation conversion,
MCP conversion, RuntimeCore results, and script results. They produce
`non_finite_number` with a value path. No string/null substitution is allowed.

## 5. Schema contract

### 5.1 Split responsibilities

`HanlinValueSchema` is a finite algebra for validation understood by all Hanlin
implementations. It may describe bytes and exact integer/binary64 constraints.
It is not advertised as JSON Schema.

`HanlinJSONSchemaDocument` contains:

- explicit dialect URI (default only after owner approval; no silent guessing
  when `$schema` conflicts);
- a lossless `HanlinJSONValue.object` root;
- optional content hash and source/provider metadata; and
- validation findings separate from the preserved source document.

Known keywords may be interpreted for host validation and model-provider
projection. Unknown keywords and unknown extension vocabularies must survive
decode, catalog storage, re-encode, hashing, and provider forwarding exactly in
semantic JSON value form. They are never moved into a generic `extensions`
bucket that changes document structure.

### 5.2 Unknown and unsupported keywords

- **Unknown but syntactically valid:** preserve; do not claim enforcement.
- **Known but unsupported by a target provider:** either retain in canonical
  catalog and omit only through a named, diagnostic-producing provider
  projection, or reject exposure when omission would broaden accepted input.
- **Security/narrowing keyword unsupported:** fail provider projection; never
  silently remove `additionalProperties: false`, bounds, required properties,
  or an equivalent narrowing rule.
- **Conflicting dialect/vocabulary:** reject validation/projection while
  retaining the original document for diagnostics.

The current MCP `inputSchemaJSON: Data` is decoded once with duplicate-key and
limit checks into a canonical schema document. Raw bytes may be retained only
as provider diagnostic evidence, not as a second authoritative schema.

### 5.3 Schema projection

Projection to OpenAI-style `[String: Any]`, MCP SDK schema values, or a future
Scripting type layer returns:

```text
projected document + preserved canonical source hash + warnings + unsupported
constraints + whether projection is exact
```

Tool exposure proceeds only when projection is exact or an owner-approved
provider policy proves that every difference narrows rather than broadens input.
Projection warnings are not swallowed.

## 6. Limits

Hard caps are host policy and apply before recursive decoding. The initial
canonical caps are:

| Limit | Default | Hard maximum |
| --- | ---: | ---: |
| Rich/JSON value nesting depth | 64 | 128 |
| Schema nesting/ref traversal depth | 64 | 128 |
| Object members at one level | 4,096 | 16,384 |
| Array items in one value | 65,536 | 262,144 |
| UTF-8 bytes in one string/key | 1 MiB / 16 KiB key | 8 MiB / 64 KiB key |
| Inline data bytes | 1 MiB | 8 MiB; larger data uses attachment handles |
| Canonical payload bytes | 1 MiB default envelope | 8 MiB hard cap |
| Schema document bytes | 1 MiB | 4 MiB |
| Total nodes | 100,000 | 500,000 |

Provider limits may be smaller and are reported during projection. Negotiation
may lower but never raise host hard maxima. Exceeded limits fail with the
measured value and configured maximum; partial truncated values are never
reported as successful conversion.

## 7. Failure shape

Every conversion returns a value or a typed failure containing:

- stable code (`non_finite_number`, `integer_out_of_range`,
  `integer_not_exact`, `binary_not_representable`, `duplicate_object_key`,
  `unsupported_schema_keyword`, `schema_projection_widens_input`,
  `depth_limit_exceeded`, `size_limit_exceeded`, or `invalid_json`);
- source and destination domains;
- JSON Pointer/value path;
- safe message;
- redacted diagnostic; and
- optional target limit/feature information.

There is no `try?` fallback to empty object, string description, zero, null, or
no result at a canonical boundary.

## 8. Required round-trip tests before any adapter ships

- Int64 minimum/maximum, JavaScript safe-integer edges, 0, -0 integer.
- Binary64 subnormals, min/max finite, signed zero, values adjacent to integers,
  and randomized bit patterns excluding non-finite patterns.
- NaN/infinities rejected from every source.
- Empty/Unicode/control-character keys, duplicate keys, and stable key ordering.
- Empty and maximum-size data, base64url validity, attachment transition.
- Deep/large structures at and beyond each cap.
- Foundation JSON and `NSNumber` boolean/number distinctions.
- MCP SDK values and schemas using the exact pinned SDK source interface.
- Unknown schema keywords, dialects, nested `$defs`/references, narrowing
  constraints, and provider projection failures.
- RuntimeJSONValue proof that integral Doubles remain number values.
- Future TypeScript/JavaScript proof on the exact shipped compiler/runtime,
  including safe-integer rejection and signed-zero policy.
- Canonical byte golden fixtures generated independently in at least two
  implementations before using hashes as integrity or identity.

## 9. Adapter deletion criteria

The old value/schema adapters may be removed only when all native descriptors,
MCP schemas/calls, RuntimeCore results, manifests, wire messages, and tests use
the split canonical types; no `[String: Any]` conversion is authoritative;
legacy manifest data is migrated or reset by approved policy; and randomized
plus golden round-trip tests pass in the exact Xcode SDK and shipped runtime.
