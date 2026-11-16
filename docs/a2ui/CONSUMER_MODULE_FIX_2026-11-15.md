# Match the real AI_Hanlin consumer module

**Native proof completed:** [run43668852483](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43668852483)
compiled source `f654ac113447177df3838908c53ce9aa24dc47ff` using consumer
module `AI_Hanlin` and test module `AI_HLYTests`. All25 actual cases passed.
Workflow SHA: `e1dba14f78e543316dd2f6c9b901cdb558bdb844`.
The owner independently checked the retained raw test tree, all13 source and
15 workflow Git byte hashes, actual harness manifest and raw lock bytes/hash/full
JSON. [Retained evidence](evidence/native-run-43668852483.json) distinguishes
these checks from Tomer's compiler-log observation and the API artifact digest.

The upstream pin remains `3ed9601862ecc78027e20ac80ad8b1b98a5d9079`.
The new raw lock SHA256 is
`af74be77f91276268a10e0b32f13e04d538f4a01110ad93d8c9e484177dd9fae`;
its originHash changed with the module manifest, while the root/transitive
revisions stayed fixed. Xcode27.2/Swift6.4.2/macOS SDK27.2 on macOS27.0.1.
This closes the isolated native consumer-name proof. Actual iOS app/test-bundle
integration, inline connection, hosted UI and physical iPad acceptance remain open.

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
at a43 passed all25 cases. That earlier result does not compile the new naming;
the f654 run above supplies that changed-source proof. Prior c40 failure,2bae
identifier pass and a43 privacy pass remain distinct retained evidence. Native
execution does not substitute for Roni's independent source-review decision.

Outside this lease, the tested verifier at workflow SHA
`eb58144679df5bb3f95692686bbeae33e7c47000` still lists `AI_HLY` as a fallback
scheme in `Scripts/CI/IntegrationValidation/run_a2ui.sh:97`. Tomer owns that
reference; it was read but not edited here. The physical archive paths at
line40 and `AI_HLYTests` filters at line108 are correct and must not be renamed.
