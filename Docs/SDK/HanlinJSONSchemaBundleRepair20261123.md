# Aggregate JSON Schema resource lookup repair — 2026-11-23

## Observed defect

Lorvex native run [45109608536](https://github.com/davidpovarsky/lorvex/actions/runs/45109608536) compiled the canonical selected SDK and executed 11 tests: seven passed, four failed. The tool-catalog failure was `JSONSchemaCompilationFailure(.metaSchema)` and prevented downstream validated tool calls. Its five new presentation tests passed; those results are not invalidated by this resource-only repair.

The original checked loader recognized `HanlinAgentSDK_HanlinExactJSONSchema`, whereas the public aggregate manifest is named `HanlinSDK`. SwiftPM therefore packages the same checked resources as `HanlinSDK_HanlinExactJSONSchema`. The resources were copied correctly but could not be found by that loader.

## Change and preserved authority

The existing checked lookup now recognizes aggregate and standalone package names in both `.bundle` and `.resources` layouts. It prefers the aggregate name within each existing candidate. The first present bundle remains authoritative: corrupt or missing contents are rejected rather than bypassed using another candidate. All nine resource lengths, hashes, parsing, quotas and cancellation checks remain unchanged. The separate WASI command-relative standalone lookup is unchanged.

`PROVENANCE.json` records this sole packaging adaptation. `Scripts/CI/verify_exact_json_vendor.py` reverses exactly the reviewed lookup block and standalone WASI spelling, then compares each entire file to its original upstream hash. It does not whitelist validation changes. The verifier passed for all 132 original files at upstream revision `f2a0d12da7028edfbcb0cb307f19a921a3a12d03`.

## Executed focused acceptance

A real SwiftPM package named `HanlinSDK` linked directly to the unchanged canonical JSON, JSONRegexRuntime and JSONSchema source directories and copied the original Draft2020-12 resource directory. Its executable loaded the official registry, compiled an object schema with a required integer property, accepted integer input and rejected string input. There were no substitute validator implementations or remote dependencies.

| Check | Actual result |
| --- | --- |
| Original loader in aggregate package | Compiled; execution failed with `.metaSchema`, exit 1 |
| Corrected loader in same cached package | Compiled in 6.98 seconds; registry and valid/invalid input checks passed, exit 0 |
| Built resource bundle renamed to standalone legacy name | Same binary passed, exit 0 |
| Aggregate bundle corrupted while a valid legacy bundle was present | Same binary rejected `.metaSchema`, exit 1 as required |
| Full original vendor source identity verifier | PASS, 132 files |

The corruption control changed one byte only in the temporary built resource, then restored it. Canonical repository resources were never modified. The first post-fix recorder assumed the older `.resources` output spelling after the executable had already passed; recorder discovery was corrected to the actual Swift Build `.bundle` output before running the two layout controls.

This is executed Oracle Linux/aarch64 evidence, not Apple native acceptance. The failing Lorvex native checks must retry on the corrected immutable SDK pin. Maktabah and Anytype must also consume the corrected pin.

## Reproduction inputs

Run from an empty temporary directory; symlink `JSON`, `JSONRegexRuntime` and `JSONSchema` to the matching directories in `Packages/HanlinAgentSDK/Vendor/Swift-JSON/Sources`, create `Probe/main.swift` below and use this manifest. Run `swift run --jobs 2 SchemaBundleProbe`. No source or package-cache patch is necessary.

```swift
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinSDK", products: [.executable(name: "SchemaBundleProbe", targets: ["Probe"])],
    targets: [
        .target(name: "JSON", path: "JSON"),
        .target(name: "JSONRegexRuntime", dependencies: ["JSON"], path: "JSONRegexRuntime"),
        .target(name: "HanlinExactJSONSchema", dependencies: ["JSON", "JSONRegexRuntime"], path: "JSONSchema",
                resources: [.copy("Resources/Draft2020-12")]),
        .executableTarget(name: "Probe", dependencies: ["JSON", "HanlinExactJSONSchema"], path: "Probe")
    ], swiftLanguageModes: [.v6])
```

```swift
import Foundation
import JSON
import HanlinExactJSONSchema
#if canImport(Glibc)
import Glibc
#endif

do {
    _ = try JSONSchemaRegistry.draft2020_12()
    let schema = try JSONParser().parse(Data(#"{ "type":"object", "properties":{"n":{"type":"integer"}}, "required":["n"], "additionalProperties":false }"#.utf8))
    let plan = try JSONSchemaCompiler().compileWithReport(schema, registry: .empty).result
    let accepted = try plan.validate(try JSONParser().parse(Data(#"{ "n":3 }"#.utf8)))
    let rejected = try plan.validate(try JSONParser().parse(Data(#"{ "n":"3" }"#.utf8)))
    guard accepted.isValid, !rejected.isValid else { throw ProbeFailure.validation }
    print("PASS: aggregate-name resource load; valid arguments accepted; invalid arguments rejected")
} catch {
    print("FAIL: \(error)")
    exit(1)
}
enum ProbeFailure: Error { case validation }
```

## Source-bound receipts

Before source SHA-256: `29cc427ec957a43ed0a768e7f0fa5daac4edc94fe707f7f9cf322daddc4c8492`.
After source SHA-256: `fd23708635df6a68605a8e215c170c01fc71e29b2e895ee13cea7faf5e330bfc`.
Before run log SHA-256: `be7d91062122bae725460aeb4f879986990097c391ad13534a64d441c75d1a6f`.
After run log SHA-256: `e184d3d5b39de96107a32004aed17f53a35833b16c5bdd53d6e835da1ed9cae8`.
Executed binary SHA-256: `ece50f134e5c81de0575a4cf1f58a288d8cbd2b3b5c2dca0f354112dea424aec`.

Original diagnostic files remain on Oracle at `build/schema-bundle-probe-20261123/` in the integration worktree. The relevant normal executable output was `PASS: aggregate-name resource load; valid arguments accepted; invalid arguments rejected`; the negative control returned the expected original compilation error.
