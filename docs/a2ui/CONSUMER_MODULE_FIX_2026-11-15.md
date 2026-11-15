# Match the real AI_Hanlin consumer module

The real PBXNativeTarget is `AI_Hanlin` (project.pbxproj line519) and uses
`PRODUCT_NAME = $(TARGET_NAME)`, with no PRODUCT_MODULE_NAME override or alias.
Existing application tests import AI_Hanlin. The physical repository directory
`AI_HLY/` and test bundle `AI_HLYTests` have different, legitimate names.

The old isolated recipe used AI_HLY as a module to match our wrong test import.
Its real25-case behavior proofs remain valid for the tested inputs, but could
not detect this app-consumer compile mismatch. The correction changes only:

- A2UITests.swift imports the actual `AI_Hanlin` module outside portable mode.
- The temporary recipe's source target, test dependency and generated
  `Sources/AI_Hanlin` folder use that same module. The planner rejects a
  different test import and records consumer/test module identities.
- The test target remains `AI_HLYTests`; all25 method identities and every
  SDK assertion/fixture, official pin and POC+DEBUG gate are preserved.

No app directory/target/product is renamed. No PRODUCT_MODULE_NAME override,
module alias, stub, shim, alternate renderer or shared wiring is introduced.
Generated-source paths change only inside the temporary proof consumer.

Actual privacy proof [run43667371439](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43667371439)
at a43 passed all25 cases. It does not compile the new consumer naming or
establish full AI app/inline-host/iOS acceptance. The new bytes require the
same changed-source proof and focused source check. Prior c40 failure,2bae
identifier pass and a43 privacy pass remain distinct retained evidence.

Outside this lease, the tested verifier at workflow SHA
`eb58144679df5bb3f95692686bbeae33e7c47000` still lists `AI_HLY` as a fallback
scheme in `Scripts/CI/IntegrationValidation/run_a2ui.sh:97`. Tomer owns that
reference; it was read but not edited here. The physical archive paths at
line40 and `AI_HLYTests` filters at line108 are correct and must not be renamed.
