# SwiftUI bridge input admission — 2026-11-23

This receipt binds a focused repair of the original public SwiftUI bridge generator at base `2549bb1395045e1514ec6c273239fcdaf18af207`. It is a developer-tool input repair, not a calendar/chat change or new cross-module bridge support.

## Observed before and after

The complete original five-file `HanlinSwiftUIBridgeCore` and actual CLI were compiled with Swift 6.4.3, Swift 6 language mode and complete concurrency checking. Compilation used the installed compiler's actual SwiftSyntax/SwiftParser host modules. No production definitions, parser or executor were substituted.

| Public route | Original observation | Fixed observation |
| --- | --- | --- |
| CLI: repeated interface module | SIGTRAP; partial inventory written | Controlled NSError/code 2; no output directory |
| CLI: different modules with same enum symbol | SIGTRAP | Controlled symbol/module ambiguity diagnostic |
| CLI: different modules with same OptionSet symbol | SIGTRAP | Controlled symbol/module ambiguity diagnostic |
| Public writer: duplicate interface identities | SIGTRAP; preexisting inventory replaced | Existing inventory, coverage and unrelated sentinel byte-identical |
| Public writer: same enum across modules | SIGTRAP; partial outputs | Controlled diagnostic before any output change |
| Public writer: same OptionSet across modules | SIGTRAP; partial outputs | Controlled diagnostic before any output change |
| Public nonthrowing classifier: enum, OptionSet, identical repeated declaration | Three SIGTRAPs | Three successful returns; every declaration/signature unsupported and exports false |
| Duplicate modules pointing at absent input | Added admission-order control | Duplicate diagnostic before attempting file parsing |
| Original valid two-interface fixture | Eight generated files | All eight files byte-identical to retained original output |

Nine original crash routes and eleven repaired controls were executed. The original CLI crash controls were retained from the initial reproduction; only the previously unexercised direct public routes were added before the fix. The repaired core, original CLI and public client compiled with zero diagnostic output.

## Policy and compatibility

A repeated module identifier cannot supply a unique interface hash. It is rejected before parser work in `buildInventory` and independently before output work in `write`.

The existing bridge resolves enum/OptionSet values and names generated wrappers by symbol, without module context. Same-symbol declarations from distinct modules are legitimate Swift input but cannot be represented safely by that current bridge. The shared admission helper lists every ambiguous symbol and its module identifiers. The throwing discovery/writer APIs reject the batch; the existing nonthrowing classifier returns the existing unsupported terminal classification for the whole rejected batch. It does not choose the first/last module, merge cases, silently emit partial compatibility, change public signatures or claim a new resolver.

The writer validates caller-constructed public inventories, not only CLI-generated inventories. Both private Swift renderers consume the same admitted index. The original parser, CLI, package manifest, SHA256 implementation and valid output formats remain unchanged.

## Evidence and limits

- `receipt.json` binds all retained files, changed/preserved source paths and all eight output hashes.
- `original-cli/` retains the actual CLI crash logs and unique-input baseline. SIGTRAP stderr is losslessly stored as `.log.gz`; the machine receipt binds both compressed bytes and original decompressed SHA256 values.
- `original-public/` retains six public-boundary crash controls against the authentic original compiled module.
- `fixed/` binds eleven controls, full source/input/toolchain hashes, commands, output preservation and zero-warning compilations.
- `Scripts/SDK/check_bridge_input_boundary.py` and `Scripts/SDK/Fixtures/BridgeInputAdmission/PublicClient.swift` exercise the complete real module and actual CLI. The four small `.swiftinterface` files are parser inputs, not replacement implementations.

The package pins SwiftSyntax **603.0.2**. These portable controls used real installed **Swift 6.4.3 host modules**; they do not establish that pinned SwiftPM/Xcode graph, generated UIKit code, hardware behavior or native UI acceptance. No existing suite or native CI was replayed. The previous native-generation-settings receipt is byte-identical.
