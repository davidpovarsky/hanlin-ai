# Preserve original import settings in full host build entrypoints

This companion to `ce876c32a9dd0f3c324222f549c4642c13f8a700` removes only four command-line `SWIFT_ENABLE_EXPLICIT_MODULES=NO` arguments from `.github/workflows/build-ios26-unsigned-ipa.yml`.

The affected existing AI_HLY scheme commands are device build, same-run device rebuild, full simulator build/build-for-testing, and same-run simulator rebuild. The command-line override would defeat the six proven consumers' explicit-module settings. Removing the override lets those target settings apply while preserving the global default for other targets. No global YES override is introduced.

The actual source comparison confirms exactly four line removals. YAML parsing confirms every other workflow field is unchanged. Four changed shell bodies pass `bash -n`; GitHub expressions are replaced with inert tokens only for syntax parsing. The original before/after bodies and raw syntax results are retained. These shell bodies were not executed.

The real original-header import mechanism is already proven by the preceding commit's fresh-cache implicit failure/explicit success on the primary Mac. That compiler proof was not repeated. This companion does not claim device or simulator app build success, a signed archive, a native test result, or any new CI run.

`receipt.json` and `validation.json` bind exact file hashes, command identities, source comparisons and raw results. Workflow inputs, conditions, concurrency, permissions, signing, uploads, other arguments and global Config remain unchanged.

Independent source review confirms these are the only command-line NO overrides in the five documented full-host workflows and four directly invoked app helpers. TestFlight archives, the other split product paths, Expo spike and performance paths have no such CLI override. Their inherited Config defaults remain unchanged. The exact reviewed scope and source commit are retained in `original-entrypoint-map.json`.
