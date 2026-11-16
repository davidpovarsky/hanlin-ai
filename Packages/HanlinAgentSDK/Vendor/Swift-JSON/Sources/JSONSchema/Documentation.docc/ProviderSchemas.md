# Prepare strict Responses schema fragments

Use explicit provider profiles to check an offline schema and preserve its declarations.

```swift
import JSON
import JSONSchema

let document = try JSONSchemaDocument(JSONParser().parse(
    #"{"type":"object","properties":{"topic":{"type":"string"}},"required":["topic"],"additionalProperties":false}"#
))
let bridge = OpenAIJSONSchemaBridge(profile: .openAIResponsesFormatV1)
let checked = try bridge.checkWithReport(document)
if checked.result.isCompatible {
    let fragment = try bridge.responseFormatWithReport(document, name: "summary")
    // The caller inserts fragment.result at Responses text.format.
    // statistics reports this complete helper operation's cumulative work.
    _ = fragment.statistics[.workUnits]
}
```

Use a separate `.openAIResponsesFunctionV1` facade and ``OpenAIJSONSchemaBridge/functionTool(_:name:description:registry:)``
for flat function tools. These helpers construct native JSON; they never make requests,
read credentials or select a model. Data/String conveniences use the same strict native
writer and preserve exact number lexemes. Every compound WithReport method accounts
for compilation, profile checking, metadata, envelope and any owned output copies in
one finite operation. Separate public calls have separate budgets; carry remaining
work explicitly, and end the application operation if a stage throws.

Optional means absent; nullable means a present null. The strict profile requires all
properties to be required and objects to declare a properties map and be closed. It rejects incompatible schemas
instead of adding required/default/null or dropping constraints. Native compilation,
profile compatibility and remote service acceptance are different outcomes.
``JSONSchemaProviderCompatibility`` retains bounded typed paths and an explicit
truncated flag. Zero issue capacity cannot turn an incompatible check into success.
Thrown resource, cancellation, IO and compilation failures are never compatibility false.

The frozen 2026-10-15.v1 base-model subset supports explicit object roots, selected
primitives/constraints, local definitions, anyOf and productive local recursion.
External references may be resolved only from an explicit registry, and remain
incompatible for export because there is no bundling policy. Unknown/unverified
keywords and unsupported combinations prevent strict export. No fine-tuned-model
support or universal provider equivalence is inferred. Conservative UTF-8 and finite
graph/depth policies are local rules; they do not define the service's character units.
Both names use an explicit ASCII/64-byte admission policy; the function policy is a
separate conservative local restriction. Full tables and source dates are in the
repository's Release1.4/ProviderProfiles.json contract.

The application owns completion. Handle transport failures, refusals and incomplete
responses first. Parse only completed output text with JSONParser, then validate the
instance against its independently compiled native plan. Invalid instances and thrown
operational failures remain distinct. A syntactically valid streamed prefix is not a
completed response. No event-envelope client or Apple model session is provided.

Public runnable examples and14 behavior checks live in
Tools/CLIQualification/Sources/ProviderConsumer. Apple GenerationSchema/DynamicGenerationSchema
bridges are a separate qualification slice and are not exposed by this increment.
