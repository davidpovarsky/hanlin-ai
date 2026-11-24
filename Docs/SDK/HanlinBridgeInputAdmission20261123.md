# Original SwiftUI bridge input admission repair

Base source: `2549bb1395045e1514ec6c273239fcdaf18af207`.

The actual original bridge generator crashed when a caller repeated an interface module or supplied distinct modules containing the same enum/OptionSet symbol. The latter is valid Swift input, but the bridge's current symbol-only type resolver and generated wrapper names cannot disambiguate it.

The shared original core now admits inputs before parsing or writing. Duplicate modules and ambiguous symbol batches use the existing `HanlinSwiftUIBridgeGenerator` NSError diagnostic surface. The public nonthrowing classifier retains its signature and returns explicit unsupported classifications for a rejected batch; it never chooses a module or claims an exported surface. Caller-constructed public inventories are checked independently, before any directory or file mutation.

The focused proof reproduced **nine original SIGTRAP paths** through the actual CLI and public core APIs. The repaired full core/CLI passed **eleven controls**, including preservation of preexisting output files and admission before missing-file parsing. The **eight output files from the original valid two-interface fixture remain byte-identical**. Public API signatures, parser, CLI and package manifest are unchanged.

Execution used the complete original module and real installed Swift 6.4.3 host SwiftSyntax modules, with complete concurrency checking and zero warnings. It does not claim the pinned SwiftSyntax603.0.2 SwiftPM/Apple graph or generated UIKit execution. No old suite or native gate was replayed.

See the [source-bound receipt and retained logs](../../docs/agent-sdk/evidence/bridge-input-admission-20261123/README.md) and [machine receipt](../../docs/agent-sdk/evidence/bridge-input-admission-20261123/receipt.json).
