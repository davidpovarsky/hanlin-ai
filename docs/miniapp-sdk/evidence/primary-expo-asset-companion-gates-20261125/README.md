# Actual Expo Asset contract gate evidence

Execution source: `1812bff50571c9907d15cd8b4bfbe4874be24756`, on the primary Mac with the original installed Xcode 27 toolchain. The normal preparation and SDK export had already completed; the preserved actual graph includes original `expo-asset@58.0.21` and `@types/react@19.3.1`.

## Actual results

- The existing manifest drift and upstream resolution Node tests executed once: 14 passed, 0 failed, 0 skipped, exit 0, 0.194 seconds.
- The existing HanlinPlatform SwiftPM route executed the exact new `HanlinScriptAnalyzerTests/expoAssetPluginRequiresItsActualEmbeddedVersion` selector once. The named test passed in 0.012 seconds; the aggregate reports 1 test in 1 suite passed in 0.013 seconds. Package dependency resolution/compilation plus execution took 318.168 seconds and exited0.
- That one unmodified Swift test checks three cases: the actual embedded Asset version is accepted, an incompatible version is rejected, and an unembedded plugin is rejected.

The first collector expected an older aggregate wording without “in 1 suite” and marked the controller failed after the actual test had passed. Its full original failed state is preserved. `output-parser-reconciliation.json` binds the precise named-test and aggregate lines to the original log SHA and original exit 0. No compiler or test was rerun; no source assertion or test scope was changed.

## Boundaries

This is source contract and upstream regression evidence. It does not establish Expo rendering, NativeScript runtime behavior, import preview latency, physical-device behavior, or the separate original 25+27 application acceptance cases. The diagnostic and original 52-case runs retain their own results.

`receipt.json` binds all six raw files and eight exact committed source inputs. The command timings are charged to the existing primary active execution budget. Capacity observations identify the admission under which these serial original commands began.
