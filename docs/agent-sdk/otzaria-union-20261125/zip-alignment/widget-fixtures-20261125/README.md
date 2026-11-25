# Original widget fixture correction and retained failure

The actual Mac archive gate at Hanlin1abcc474 reported five issues: the Counter and Visuals archives violated the strict embedded Expo widget contract in both analyzer/installation tests, and ScriptWidget Actions failed native preparation. The original18 compiler/archive invocations passed. These fixture/source controls do not qualify native widget preparation.

The shared original generator now reads Scripts/Expo/dependency-lock.json. The product analyzer remains unchanged and strict. Original7b8cbba was separately applied in full with provenance for the MiniApps picker; Coreabf and ZIPFoundation0.9.20 remain unchanged.

Actual Mac job417ce382f9ae ran the original generator and eight unchanged Node source controls successfully using Node22.23.5. Its initial post-generation validator failed because it expected only four ZIP streams to change. RESULT.json is retained unchanged as FAILED. POST_GENERATION_AUDIT.json independently validates the same actual outputs and logs without rerunning those controls: all21 archive copies agree in their three original locations; all ZIP metadata and all uncompressed members are byte-identical except four expected package.json version contracts. The other archive byte changes are compressor output differences, with before/after member hashes and compressed sizes retained. The original SHA256 manifest is preserved as SHA256.before.json.

The generation input is exact committed3f622f786bcd493d9068f35ad0b149d49d6fd793 with31 path/mode/Git-blob/SHA input bindings. Four Expo declarations now match58.0.29. Mixed/Invalid negative inputs and all ScriptWidget/legacy source payloads remain unchanged. Eight Node controls include real original JavaScript compilation and source action execution; they are not Apple native widget acceptance. The separate Swift diagnostic retains all original assertions and now records the actual preparation failure reason.

Pending: actual original Swift widget continuation, final shared source graph check and consumer-pin resolution, then integrated app acceptance.
