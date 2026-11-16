# ``JSONSchema``

Draft 2020-12 compilation, evaluation and declaration inspection over exact JSON.

Create a ``JSONSchemaDocument`` from an object or boolean. Supply external
resources explicitly through an immutable ``JSONSchemaRegistry``. The compiler
resolves RFC 3986 resource identities, Pointer/anchor fragments, vocabulary
requirements and static targets into an immutable ``CompiledJSONSchema``.
There is no runtime network resolver. Ambiguous identifiers and anchors fail.
Official packaged meta-schemas are pinned, integrity-checked and evaluated by a
staged bootstrap before caller schemas are accepted. Custom meta-schemas using
supported vocabularies can be supplied in the registry.

``JSONSchemaValidator`` evaluates through explicit invocation-owned frames.
Productive recursive references can revisit another instance location;
nonproductive active states throw ``JSONSchemaEvaluationFailure``. Operational
failures, cancellation and resource exhaustion are never invalidity verdicts.
Numeric assertions are exact. String length counts scalars. Evaluated property
and item locations flow only through the successful branches required by each
applicator, including `contains` and `unevaluated*`.

Format is an annotation by default. The format-assertion vocabulary or the
explicit `formatAssertion` option enables native recognizers. Unknown formats
in a required format-assertion vocabulary fail compilation; an unknown name in
explicit optional assertion mode remains an annotation. Internationalized
recognizers use fixed Unicode 13.0.0 nontransitional STD3 UTS46 mapping, NFC and
IDNA2008/contextual/bidi checks. Content keywords remain metadata and do not
automatically decode or parse instance content.

The package-private regex VM targets ECMA-262 11th edition (2020), with fixed
case-sensitive Unicode u-equivalent behavior and unanchored scalar searches.
It supports classes/properties, captures/backreferences, counted/greedy/lazy
repetition and directional lookarounds. It has compilation, forward scanning,
state, capture, aggregate work and cancellation budgets. Identical programs
are shared by exact spelling within one plan; each search owns its state.
There is no Foundation regex fallback or public regex product.

## Results and declarations

``JSONValidationResult`` contains the verdict, structured issues, optional
annotations and a diagnostic completeness indicator. `output()` adapts the
recorded result to flag/basic Draft 2020-12 output JSON. A flag-only result
cannot be upgraded to invent basic errors. Complete output capacity failure
throws; best-effort diagnostics explicitly report incompleteness while semantic
work still completes. Detailed/verbose output are outside this API's formats.

``JSONSchemaNodeView`` exposes raw declarations and exact constraints, resource
identity and optional static/initial dynamic reference targets. Declarations
are not inferred effective schemas, do not insert defaults and cannot promise
final dynamic targets without an evaluation scope.

## Cumulative public work reports

The compiler's raw JSON `compileWithReport` overload includes document admission
and compilation in one meter. Its document overload begins after construction.
Use parser, compiler, validator and writer reports to carry a checked remaining
work allowance across separate public calls. WorkUnits includes subsystem work;
subtract it once and retain subsystem ceilings separately. A failed stage ends
the composed operation because successful reports cannot describe failed work.
Internal mutable meters remain private.

## Topics

### Guides

- <doc:OfflineValidation>
- <doc:ProviderSchemas>
- <doc:CompiledPlanConvenience>

### Documents and plans
- ``JSONSchemaDocument``
- ``JSONSchemaRegistry``
- ``JSONSchemaURI``
- ``JSONSchemaBuilder``
- ``JSONSchemaCompiler``
- ``CompiledJSONSchema``
- ``JSONSchemaCompilationFailure``

### Evaluation and output
- ``JSONSchemaValidator``
- ``JSONSchemaOptions``
- ``JSONValidationResult``
- ``JSONValidationIssue``
- ``JSONValidationOutput``
- ``JSONSchemaEvaluationFailure``

### Declaration inspection
- ``JSONSchemaNodeView``
- ``JSONDeclaredAnnotations``
- ``JSONSchemaReferenceTarget``

### Provider request fragments
- ``OpenAIJSONSchemaBridge``
- ``JSONSchemaProviderProfile``
- ``JSONSchemaProviderLimits``
- ``JSONSchemaProviderCompatibility``
- ``JSONSchemaProviderIssue``
- ``JSONSchemaProviderIssueCode``
- ``JSONSchemaProviderMetric``
- ``JSONSchemaProviderFailure``
