# Hanlin App07 impact review for the Otzaria freeze

## Decision

Keep the shared Hanlin source at `1abcc4749056d4c1c364f378732e137e7fead8b3`, which preserves the qualified a11 union and applies the required original ZIPFoundation 0.9.20 alignment. The root integration owner confirmed this decision on 2026-11-25 after the read-only comparison below. This does not award acceptance to any unexecuted UI, SDK, archive, or Live test.

The fixed dependencies are Core `abf0921c6e89e6521cc2b510ff11016b45a0ef08`, ZIPFoundation 0.9.20 `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`, OpenTelemetry 2.6.0 `c6fcee77cfc21ba400366f12475217c7b6e1d605`, and Atomics 1.3.1 `0442cb5a3f98ab802acb777929fdb446bda11a34`. The six standalone package locks are actual SwiftPM output; their generation and resolution evidence is committed separately.

## Exact incoming evidence examined

The qualified newer application source is `948bdb1fe75d31559dc8d65ae8d2e70fa69de276`. Its proof was read from commit `1f27a36e257573df0a74ec5b3b0ca3586f6854ad`, under `docs/ai-cache/evidence/app-native-20261125/attempt07/test/`.

| Original artifact | SHA-256 |
| --- | --- |
| receipt.json | a5c0fabfecc9cc6bc5169e139e23ea838597eadb28836ac60aa1a15a8d008d13 |
| acceptance-summary.json | 37063f29d24518e5ca5532d868cd7f06b32d528cb5863e7440feec1b5fc26055 |
| expected-test-inventory.json | beeec6c308cf24ec9c6c1ad6d7d35e4b06a4a38e81e79a80dbbef416b1dff190 |
| 11-verify-exact-test-invocations.json | fbe39b3c63968420878d574cbd84a1ff2fbec30f5b2b92a50490006c11ebb519 |
| Original raw test log (receipt binding) | 07c830e0b4fb16158ffe41a6e584a14b75635fa3c9a5aaefe5d2191f8f499f07 |

The actual original run was 05:05:53–05:09:35 UTC. It reports 46 methods and 48 required invocations, all passed, with unchanged source and active locks and successful shutdown of its owned simulator. Its four suites are ClassicChatRestorationTests, HanlinMiniAppAssistantIntegrationTests, HanlinModelPromptCachePersistenceTests, and HanlinPromptCachingIntegrationTests. These are the original application's focused acceptance suites. They do not include HanlinComposerCapabilitiesUITests, HanlinMorphComposerUITests, or Maktabah Live.

App08/App09 later failed during builds and executed zero tests. App10 remains outside this qualified source decision. Their failures and independent owners' ongoing work are preserved without attribution to our source.

## Composer comparison and the actual Otzaria consumer

The shared Composer delta from a11 to 948 changes three original HanlinChatUI files:

- HanlinCapabilityConfigurationView.swift adds FocusState reporting for string and numeric capability inputs.
- HanlinCapabilityPicker.swift reports focus of its capability search field.
- HanlinComposerFieldFocus.swift adds an additive preference key and a view modifier through which hosts can include those fields in their existing keyboard owner.

The original Hanlin application's HanlinCompactChatWorkspace consumes that preference, and ChatViewBottom includes capability attachments, invalid configurations and capability suggestions in its accessory-row visibility calculation.

The current Otzaria source contains no direct references to the capability picker, capability configuration view, or new focus preference. Its actual OtzariaHanlinChatView composes the original HanlinMorphComposer and NativeMultilineTextEditor with its appearance picker and empty detail panel. Therefore this incoming capability-panel focus work does not supply a missing call path in the current Otzaria consumer.

The original Otzaria fix `d3da55417a30e9a06b0255e2d0b561955034b260` remains in its chat view: the transcript ScrollView uses `.safeAreaPadding(.bottom, composerHeight)` so auto-follow places the last message above the floating composer. The newer capability-field preference is independent of that source-action hit-testing correction. The latter still requires a genuine Live interaction in the integrated Otzaria application. A source comparison is not a passing Live receipt.

The exact consumer commit and file hash observed during this review are in the adjacent JSON receipt.

## Remaining changes and proof reuse boundaries

The full non-document change inventory was inspected rather than inferring equivalence from the three Composer files alone. It includes the two original Hanlin consumers above, original application's optional-system-startup sequencing and artifact-root lookup, original Node miniapp authoring changes, original UI and assistant fixtures, modular text-search disclosure and host-services probe fixtures, six standalone lock updates, and the standalone lock resolver guard.

The diff of `Packages/HanlinPlatform/Sources`, `Packages/HanlinPlatform/Tests`, `Packages/HanlinPlatform/Package.swift`, and `Packages/HanlinCore` is empty between a11 and 948. No wholesale Core retest is justified by the capability-focus delta. Our required ZIP version change is separately qualified against the original archive tests at the exact 1abc source. Its pending/actual status must be read from that gate's own receipts; this document grants no archive-test success.

If a future actual Maktabah acceptance exposes a need for the incoming functionality, use a normal reviewed union retaining the actual ZIP 0.9.20 lock output, verify the canonical package graph, and run the affected native/UI acceptance. Do not transplant a passing App07 count onto a changed ZIP or Maktabah UI build.

## Review scope

This is a read-only source and original-receipt review. No application source, test assertion, dependency lock, or acceptance threshold was edited. Existing Core7, Core48, C8/App05, App07, Library7 and Multipart37 proofs remain attached to their own exact inputs. Final SDK provider ownership, integrated consumer resolution, app build, Maktabah Live and final UI/library gates remain required.
