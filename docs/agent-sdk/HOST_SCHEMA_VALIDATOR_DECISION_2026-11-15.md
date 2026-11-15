# Host schema validation: source findings and dependency proposal

No dependency has been added by this proposal. Existing application tools/OS permissions remain
the effect authority; a validator must complete before their original closure is entered. A known
pre-dispatch denial is not an uncertain post-dispatch mutation. No permission registry or parallel
hand-written JSON Schema value engine should be introduced.

## Why the existing subset is insufficient for broad Host/MCP inputs

Pinned producer e7bf's `AISDKProviderUtils.jsonSchema` delegates to its existing subset validator.
It ignores unknown assertions, treats false root/nested schemas permissively, uses UTF-16 string
length, projects all numbers to Double, and compares String-based keys/values with Swift canonical
equality. Local reference processing is not a complete2020-12 reference/sibling/dynamic model.
Its multipleOf remainder tolerance1e-9 can admit1e-10 as a multiple of1. These are source findings,
not a new complete-dialect test pass. A portable Swift probe confirms K equals Kelvin-sign under
Swift equality and Double merges9007199254740992/9007199254740993; it is not an SDK acceptance test.

Producer correction `febe93e2717a9a647ae85feccb97117e72d6e176` fixes only false schemas and Unicode
scalar length while preserving Foundation regex UTF-16 ranges. Three focused controls added to
the actual25-case JSONSchemaValidator suite cover root/nested booleans, supplementary/combining
strings and the public facade. Its Apple proof is pending; consumer/foundation pins remain e7.
The local design-decision record preserves this narrow boundary, with no full validator claim.

JSON Schema's [boolean rule](https://json-schema.org/draft/2020-12/json-schema-core#section-4.3.2),
[length rule](https://json-schema.org/draft/2020-12/json-schema-validation#section-6.3.1) and
[unknown-keyword annotations](https://json-schema.org/draft/2020-12/json-schema-core#section-4.3.1)
mean an adapter must neither accept unsupported assertions nor blanket-reject descriptions or
legal extension metadata. A large manual capability/value filter would itself become another
incomplete engine and block ordinary Unicode+enum tools; that is not the proposed implementation.

## Released candidates inspected at their actual source

- `ajevans99/swift-json-schema` v0.15.0, commit
  `a00dde585b7f55b343214cece9afcfeb613e7899`, MIT: current OrderedJSON has lossless number tokens
  and scalar-based string equality. Its object representation still uses OrderedDictionary keyed
  by Swift String, and object equality looks up those String keys. Exact distinct Unicode keys
  therefore require further qualification; a README feature list alone is not sufficient.
  [Actual value source](https://github.com/ajevans99/swift-json-schema/blob/a00dde585b7f55b343214cece9afcfeb613e7899/Sources/OrderedJSON/JSONValue.swift).
- `ThorFuchs/Swift-JSON` stable1.9.0, annotated tag resolves to commit
  `f2a0d12da7028edfbcb0cb307f19a921a3a12d03`, Apache-2.0. The released manifest has no external
  dependencies; JSONSchema depends only on its JSON and JSONRegexRuntime targets plus bundled
 2020-12 resources. Swift tools6.4 is required; its macOS15/iOS18 minimums fit this SDK's
  macOS26/iOS27. Installed Apple compiler6.4.2 can qualify it; workstation Swift6.3.3 cannot.
  [Actual manifest](https://github.com/ThorFuchs/Swift-JSON/blob/f2a0d12da7028edfbcb0cb307f19a921a3a12d03/Package.swift).

The second candidate's actual JSONKey compares exact UTF-8 scalar spelling, not String equality.
Its compiler consumes an immutable explicit offline registry, checks dialect/meta-schema/vocabulary
and resolves references without network fetch. Compiled plan validation distinguishes invalidity
from thrown budget/configuration/cancellation failure. Options expose finite limits, complete
diagnostics and format-annotation default. These are inspected APIs/implementation, not yet a
Hanlin compatibility pass. [Key implementation](https://github.com/ThorFuchs/Swift-JSON/blob/f2a0d12da7028edfbcb0cb307f19a921a3a12d03/Sources/JSON/Value/JSONKey.swift),
[compiler](https://github.com/ThorFuchs/Swift-JSON/blob/f2a0d12da7028edfbcb0cb307f19a921a3a12d03/Sources/JSONSchema/Compilation/JSONSchemaCompiler.swift),
[plan validation](https://github.com/ThorFuchs/Swift-JSON/blob/f2a0d12da7028edfbcb0cb307f19a921a3a12d03/Sources/JSONSchema/Compilation/CompiledJSONSchema.swift).

## Proposed narrow integration

Pin the released second candidate exactly, scoped to HanlinAgentCore (JSON/JSONSchema products),
not PlatformContracts, MiniApps, a renderer or a second canonical value/store. A small SDK facade
accepts the existing canonical schema/input bytes into a transient validation AST and discards it
after the verdict. Reuse immutable bounded compiled plans per original descriptor/schema revision;
live Host context/permission checks still repeat after every await and immediately before the
existing executor. No remote refs are fetched. Missing resources, unsupported dialect/vocabulary,
budgets/cancellation and invalid arguments return typed pre-dispatch results with known no effect.

Before adoption, execute actual source-bound controls for invalid required/type/additional fields,
local refs and legal annotations, exact2^53 boundaries/multipleOf, distinct scalar strings/keys,
valid Hebrew/emoji inputs, false schemas, unsupported external/vocabulary paths, cancellation and
finite exhaustion; then actual app original-closure/OS-policy/row/storage controls. Retain license
and exact resolved source evidence. Required unsupported MCP resources/dialects remain explicit
compatibility obligations. Frozen80 remains e7. No full Host/MCP readiness is claimed here.
