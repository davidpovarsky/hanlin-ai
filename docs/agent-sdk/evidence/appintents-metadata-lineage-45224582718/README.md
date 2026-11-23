# AppIntents source and metadata lineage — failed run 45224582718

## Finding

The retained evidence supports a **fresh compilation of the local, fixed HanlinWidgetSDK package**, followed by a failure in the original AppIntents metadata processor. It does not support a stale DerivedData object or a separately resolved remote Hanlin package as the cause. A second full clean build is not warranted by this cache evidence.

Run [45224582718](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45224582718) used source `8429dbb6cb66e266504b8d055586829ba7aa61f7`. Runtime preparation/preflight, native export verification and SwiftPM resolution passed; AppIntents extraction failed with nine diagnostics. All 32 selected app/native scopes remained **NOT_RUN**. The producer is **ineligible for native asset publication** despite its successful preparation/export steps.

## Observed input chain

1. The raw job log fetches and checks out the exact source SHA. Both package source files are byte-identical in that commit and the earlier `.main` fix `b6c3d250ce28149a3170f7a04bdb021c8784d285`; their Git blobs, SHA256 and nine fixed declaration lines are bound in the receipt.
2. The retained cache report states `SourcePackages=exact-hit`, `DerivedData=miss`, `build_mode=cold`, and `DerivedData_save=skip_failed_job`. Input metadata restoration says `status=no-manifest`; the cache restore implementation returns without rewriting content or restoring timestamps in that case.
3. SwiftPM resolves `HanlinSDK` from the current `/Users/runner/work/hanlin-ai/hanlin-ai` workspace as a local package. It is not resolved from a SourcePackages checkout or another SDK revision.
4. At 17:33:27–28 UTC the compiler emits const values and compiles both original `Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/*.swift` inputs. The package module is `HanlinScriptingWidgets`; the separate original app extension module is `HanlinScriptingWidgetsHost`. Their compilation products and source lists are separate.
5. At 17:33:40 the original `appintentsmetadataprocessor` consumes the package's just-built object, source list, dependency metadata lists and SwiftConstValuesFileList from `HanlinSDK.build/.../HanlinScriptingWidgets-t.build`, with `--force --compile-time-extraction`. It emits all nine bundle diagnostics at the fixed source locations.

## Workspace modifications and dependency resolution

The provenance says `trackedWorkspaceModified=true`; this must not be silently described as a byte-clean checkout. A concrete retained difference is `Package.resolved`: its hash changes from `28fb383e35bd875dd91b124ad02ca4210da7771c53daf4c6c6d28c1e2a55e529` to `6634fc599022b6cee5d3c1a5b6f6395f2aba9ab5cd565cde4b0f0712bdaf4b0e`.

Comparison proves **all 39 resolved dependency revision SHAs remain identical**. Nine records lose their old version label, two repository URLs normalize their `.git` suffix, and the origin hash changes. This observed tracked change explains why a modified-workspace flag can be true without a Widget SDK source rewrite; it is not a claim that the lock was the only changed tracked file.

The recorded preparation path stages NativeScript/Expo dependencies, RuntimeCore resources, diagnostics provenance, modular headers and A2UI output. The localization source-rewriting tool `route_shared_resources` has no invocation in the complete raw job log. No AppIntents source rewrite was identified in the reviewed preparation steps. There is no recorded cache restoration of the Widget source or its const metadata.

## Evidence limits

The authenticated [simulator-smoke artifact 14847381090](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45224582718/artifacts/14847381090) contains logs, provenance, a resolved lock and an xcresult. It contains **no archived raw `.swiftconstvalues`, `.stringsdata`, SwiftFileList or dependency metadata list files**. All three xcresult zstd data records were decoded read-only on Oracle; they contain build/issue records and command references, not those raw const-value payloads. The decoded build records show the projected `HanlinAppIntents.xcstrings` catalog being processed, but no old `.atURL` source text.

Therefore this review cannot inspect the exact chosen initializer overload or claim an independently retained byte-for-byte snapshot of the two compiled Swift files. It narrows the failure to the current source/const-extraction interpretation with explicit provenance limits. The root owns the syntax/API correction and the next necessary native verification. No product code, cache, runtime or workflow was changed here; no native test was run.

## Acquisition

The full native job log was reused from the root's existing download and its SHA256 verified; it was not downloaded again. Only the simulator-smoke artifact was acquired once in this lane. Its 1266108 bytes match SHA256 `be88328bf26dfa0e4f7c6661fd5070e5e9138f81186515603ad00310860e641b`, and every ZIP entry passed CRC validation. Relevant raw artifact files, exact selected job lines, the complete extractor block, source/dependency comparisons and all artifact entry hashes are retained alongside this report.
