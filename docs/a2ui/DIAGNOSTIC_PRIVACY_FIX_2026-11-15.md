# Diagnostic privacy correction after 2bae5a3e

**Native execution now recorded:** a43 passed all25 actual enabled cases in
[run43667371439](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43667371439),
including the canary assertions below. The later consumer-module naming fix
needs its own changed-source proof; it does not invalidate this privacy result.

Actual [run43664698104](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43664698104)
compiled2bae5a3e and passed all25 cases, validating the identifier correction.
That result does not cover the new privacy assertions or accept raw SDK paths.

SDK detail paths interpolate component IDs, function names and argument keys;
truncation did not anonymize them. The old error callback also forwarded raw
SDK errors. Both diagnostic boundaries are corrected together:

- SDKDiagnostic has no path field. A private finite enum stores only known
  codes; unknown codes become `SDK_ERROR`. `invalid_identifier` is preserved.
- Error types exact-match known SDK names and become fixed literals; unknown
  types become `A2UIError`. No input substring/prefix/suffix is retained.
- Rejection retains only failure, verified owner correlation, fixed error type
  and up to8 safe codes. Descriptions/reflection/localized rendering have no
  SDK message, path, expression, component ID or argument key to echo.
- The callback sanitizes the code immediately and never captures a raw SDK
  error in its queued task. MainActor checks membership in the existing SDK
  surface map. Official error models get a fixed message; the validation
  model's required path is the constant `validation` category. Generic errors
  have no path/expression. Official JSON encoding/decoding remains valid.

User-action context is unchanged. The surface ID remains the existing verified
correlation identity, not an SDK payload-path segment. There is no new authority,
validator normalization, RPC allowance, lifecycle change or upstream modification.

The same25 cases are amended with deterministic canary regressions:

- Portable componentValidationRemainsWithSDK checks unknown code/type sanitizing,
  every Rejection field, description, reflection and localized rendering. Stable
  known code/type must survive. This is executed local coverage, not SDK proof.
- SDK officialSchemasRejectInvalidTextInputButton keeps all4 fixture negatives,
  then submits an invalid canary component ID to the actual SDK. It requires
  invalid_identifier and no canary in local or callback diagnostics.
- SDK unknownFunctionsAndUnsolicitedResponsesCannotEnableRPC keeps all prior
  no-RPC checks, then submits canary function/argument identifiers. Codes must
  remain stable; JSON, description, reflection and decoded callback roundtrips
  must contain no canary. Actor-safe callback waits are bounded and event-driven.

Leak assertions emit only Boolean/fixed failure text. The canary is public
synthetic test input, not private data. Evidence planners retain source hashes,
repository paths and fixed case names; they do not export runtime SDK paths.
The identifier probe reads only authored public fixture files, not application
traffic. No application payload was logged. Existing failed-c40 and passing2bae
artifacts are preserved separately. Counts remain8 portable +17 SDK =25;
the a43 privacy proof is retained and the later consumer-name bytes need their
own enabled proof and focused QA.
