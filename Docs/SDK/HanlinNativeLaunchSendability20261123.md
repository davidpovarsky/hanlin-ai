# Public original navigation value sendability — 23 November 2026

The actual full-app native run [45144384416](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45144384416) at `9e4fbcbdeed05aa8dea0ab3c55997a73383f92b4` passed native preparation and exported all14 original frameworks plus4 support archives. Its app build then failed at `ChatPresentationBridge.swift:30`: `ChatResolvedExpansion` is Sendable, but its imported `NativeAppLaunchRequest` was not. No selected unit or UI case ran, and this failed producer remains ineligible for native publication.

The original internal value declarations received implicit sendability inside the app. The SDK extraction made those declarations public, which requires an explicit public conformance across the module boundary. The two original Foundation files contain only UUID, String, string dictionaries, optionals and the same value types.

The repair adds compiler-checked `Sendable` to exactly four declarations: `NativeAppPresentationStyle`, `NativeAppLaunchRequest`, `NativeAppRoute` and `NativeAppRoutePayload`. Every byte of the original files is identical after removing those four added conformance tokens. There is no new unchecked conformance, isolation relaxation, stored property, serialization change, navigation behavior or UI change.

## Verification

The two complete original files were compiled as a separate public module using Swift6, complete strict-concurrency checking and warnings as errors. An actual importing client reproduces the original failing Sendable stored-property boundary and requires all four public types to be Sendable. Before the repair the module builds but the external client fails on the original missing-conformance diagnostic; afterward both compile successfully. This is a real public-module compiler check of the original files, not a full Apple application build or runtime/UI test.

The [compiler receipt](../../docs/agent-sdk/evidence/native-launch-sendable-45144384416/receipt.json) retains before/after source and log hashes, the [importing client](../../docs/agent-sdk/evidence/native-launch-sendable-45144384416/ExternalClient.swift) and complete-file preservation evidence. [The native artifact receipt](../../docs/agent-sdk/evidence/native-launch-sendable-45144384416/native-artifact-receipt.json) authenticates artifact14803689577 (1,147,047bytes, SHA256 `6d71d190ca1cfef2521cd81d8a2873a0065b259ad7a30e2e48164278098c1cd4`), all ZIP CRCs, and the original8,149,579-byte Xcode log SHA256 `590a9b0f95e26b4451fe2b5f2fa219617a5cd361f9f0c075a1196dffe5f86094`.

The existing26 selected full-app unit/UI selectors still need the corrected native gate. The paired MiniApps UI retry waits for that compiler qualification. The preceding Widget import issue is resolved in this failed run; this receipt records the next concrete public-type boundary rather than repeating that diagnosis.
