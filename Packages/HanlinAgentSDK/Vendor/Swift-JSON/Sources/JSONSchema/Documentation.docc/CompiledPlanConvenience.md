# Validate a compiled plan

Compile explicit offline resources once. The convenience evaluates the immutable
snapshot with independent per-call state and evaluation options.

```swift
let document = try JSONSchemaDocument(JSON.parse(#"{"type":"integer","minimum":0}"#))
let plan = try JSONSchemaCompiler().compile(document)
let before = try JSONSchemaValidator().validate(42, against: plan)
let after = try plan.validate(42)
precondition(before.isValid && after.isValid)
let invalid = try plan.validate(-1)
precondition(!invalid.isValid)
let report = try JSONSchemaValidator().validateWithReport(42, against: plan)
precondition(report.result.isValid && report.statistics[.evaluationWorkUnits] > 0)
```

False is a completed invalid verdict. Evaluation errors, resource exhaustion and
cancellation throw. No compilation, online resolution, default insertion or
upgrade of unavailable diagnostics is hidden in validate. Options are evaluation
options; compilation settings do not become implicit evaluation defaults.
Use the validator's report API for cumulative successful accounting. After an
error or cancellation, a composition cannot recover unreported work by retrying
with a fresh quota. See <doc:OfflineValidation> for dialect and output policies.
