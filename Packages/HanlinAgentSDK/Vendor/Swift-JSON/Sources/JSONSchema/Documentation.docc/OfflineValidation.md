# Offline schema validation

Compile explicit resources once, then evaluate independently with exact semantics.

## Choose the instance root

``JSONSchemaDocument`` accepts object and Boolean declarations. A document with
only `$defs` does not automatically select a definition for instance validation.
Create a root `$ref` to the definition you intend to validate. Raw declarations,
unknown metadata and exact number constraints remain available for inspection.

``JSONSchemaBuilder`` constructs the same ordinary declarations. Its object helper
shares a cumulative budget across member construction and document admission,
including live object state overlapping admission scratch. Catching an owned quota
failure or cancellation in the callback cannot make finalization succeed. Replacing
the borrowed accumulator with a new invocation is rejected. Compilation
remains a separate call; callback execution itself is caller-owned work.

Supply external documents with unambiguous retrieval identities through
``JSONSchemaRegistry``. Compilation never fetches a URL. Packaged official
meta-schemas are pinned and integrity-checked. Required unsupported vocabularies
and unresolved references fail compilation.

```swift
let document = try JSONSchemaDocument(JSONParser().parse(
    #"{"type":"integer","minimum":0}"#
))
let plan = try JSONSchemaCompiler().compile(document)
let result = try JSONSchemaValidator().validate(42, against: plan)
```

``CompiledJSONSchema`` is immutable and Sendable, including plan-local shared
regex programs. Each validator call creates independent frames, annotations,
dynamic scope and regex search state. Synchronous evaluation uses the caller executor.

## Separate invalidity from failed work

A completed ``JSONValidationResult`` with isValid false means the instance is
invalid. A compilation error, nonproductive reference, exhausted work/state quota
or cancellation throws and produces no verdict. Operational errors propagate
through alternatives instead of becoming failed assertions.

Numeric constraints are exact and string length counts Unicode scalars.
Evaluated locations flow through the successful branches required by applicators,
including contains and unevaluated keywords. Required internal annotation state is
bounded even when output annotation collection is disabled.

Format is annotation by default; explicit assertion or a required assertion
vocabulary enables native recognizers. Content metadata does not decode instance
text. The private regex engine uses the documented ECMA-262 2020 fixed Unicode 13
case-sensitive u-equivalent dialect. Matching is unanchored unless the pattern
anchors itself; compilation, candidate scans, captures, states and cancellation
remain budgeted. There is no unbounded fallback.

## Inspect declarations and produce output

Document/plan node inspection returns immediate raw declarations. Compiled views
may expose resource identity and initial reference targets. Dynamic evaluation can
replace an initial target; inspection alone cannot compute its final scope.
Defaults are declarations and never mutate an instance.

``JSONValidationOutput`` supports flag/basic. A flag-only result cannot invent
basic issues. Complete diagnostic policy throws on retention exhaustion; best-effort
policy marks diagnosticsComplete false while semantic evaluation still completes.
Output adaptation is separately bounded and does not re-evaluate the instance.

Raw compiler compileWithReport includes admission and compilation together.
The document overload begins after construction. Public successful reports allow
checked remaining-work composition; an error/cancellation ends that composition.

## Topics

- ``JSONSchemaDocument``
- ``JSONSchemaRegistry``
- ``JSONSchemaCompiler``
- ``JSONSchemaValidator``
- ``JSONSchemaNodeView``
- ``JSONValidationResult``
