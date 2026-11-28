# iOS and iPadOS 27 application UI acceptance packet

This packet adds three focused tests to the existing `AI_HLYUITests` application target. They drive the real app with its existing `HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE` seeded chat and `HANLIN_DOCK_ACCEPTANCE_FIXTURES`; those flags are fixture-backed service/data inputs, not proof of a production backend. The test target uses the synchronized `AI_HLYUITests` folder at base `4c6de549bb5c45b770e2f174676b1a4b110b1cee`. Test source and this plan are not execution evidence.

**Destructive fixture boundary:** at the base, `AgentRuntimeUIAcceptanceProvider.configureIfRequested` deletes all chat records, models, API keys and user info in its model context; enabling dock fixtures also deletes prompts. It re-seeds on each launch. Run this packet only on a newly created, dedicated disposable simulator and app container without user data or synced accounts. Never run it on a personal or shared simulator. The seeded-chat navigation test does not test persistence across relaunch. Source gates this provider on `targetEnvironment(simulator)`, not `DEBUG`; Release simulator compilation and runtime availability remain unverified and must be checked on the actual candidate before any Release claim.

The runner must set `HANLIN_SIM_ACCEPTANCE_LOCALE` in the **test bundle** environment to `en` or `he`; the helper applies the corresponding app language and locale and sets `HANLIN_UNIT_TEST_HOST=0`. Missing cohort fails setup and a different cohort skips the fixed-language case; skipped is not a pass. The case-level contract is `coverage.json`; its tags describe asserted behavior only and do not satisfy untested keyboard, real Dynamic Type readback, forms, transition quality, error/recovery, additional products or window obligations.

## Existing coverage assessed at the base

`HanlinPrimaryNavigationSmokeUITests` visits primary tabs and returns to Apps. `HanlinMorphComposerUITests` covers English compact/wide navigation, draft retention during panel interactions, an attachment, resize gesture and a Chinese parameter dismissal; it has device-width preconditions. `AgentRuntimeConversationUITests` contains fixture-backed chat and error/diagnostics paths. `HanlinSkillCenterUITests` contains settings/skill interactions. These cases must be individually evaluated and run, or reused only under the evidence rules below; their existence does not establish a pass. Do not relabel isolated tests or an unconfigured shell as whole-app acceptance.

## New focused cases and required environments

Run each of the three methods in `HanlinSimulatorAcceptanceUITests` on actual iOS 27 iPhone and iPadOS 27 iPad simulators. Record the exact simulator model, UDID, OS build, app and test bundle hashes, source commit and dependency tree, Xcode version, locale, orientation and test identity for each execution. Each combination is an independent case, not an inferred duplicate. The six planned executions are **NOT_RUN** as of source preparation.

| Case | Locale/settings | iPhone portrait and rotation | iPad portrait and rotation | Meaning |
| --- | --- | --- | --- | --- |
| `testEnglishDraftSurvivesPortraitLandscapeRoundTrip` | English, default text | NOT_RUN | NOT_RUN | Real text entry, both observed orientations, draft and window bounds |
| `testHebrewLargeTextPanelRoundTripPreservesDraft` | Hebrew/RTL, accessibility XXXL | NOT_RUN | NOT_RUN | Real launcher placement, panel open/close, draft and window bounds |
| `testDraftSurvivesLeavingAndReturningToSeededChat` | English, default text | NOT_RUN | NOT_RUN | Navigate to the list and back to the same fixture-backed chat; exact draft readback |

Within the first case both orientation changes are assertions of that single test. Require one compact iPhone and one wide iPad; record window dimensions observed, and separately add compact iPad window/split view where the runner actually supports it. No unsupported split view, physical device, animation quality, keyboard overlap or VoiceOver result may be inferred from these tests. Large text uses an app launch argument; confirm the actual size in simulator evidence rather than assuming acceptance from the argument alone. Tests retain a final screen attachment; runner must also retain raw xcresult, launch/build/test logs, test tree, initial/intermediate or failure screenshots and exact selected runtime/device provenance.

## Outstanding acceptance obligations

An actual iPhone+iPad screen and journey inventory is still needed for all required product areas, including form submission/validation and recovery, meaningful gesture and transition behavior, compact and wide iPad windows, keyboard occlusion, Dynamic Type, Hebrew/English, and reopening/restoring state. Coordinate missing accessible identifiers and deterministic error inputs with the owning source teams. A scenario blocked by app build, missing fixture, unavailable simulator configuration or inaccessible control is **BLOCKED/NOT_RUN**, not a pass. This small packet alone does not satisfy CHATUX08, FINAL, SplitH, SDK08 or TestFlight acceptance.

## Execution and reuse contract

Tomer owns the Mac runner, workflow and retained artifacts. Run the actual application UI target, not a substituted component harness. Do not reset another user's simulator or data. Retain result bundle, raw logs, screenshots, per-test outcomes and full source/dependency/toolchain/runtime/device/locale evidence even on failure or pre-test blockage. A case can be `REUSED_VERIFIED_PASS` only when an original successful artifact and versioned acceptance contract demonstrate equivalence of that case's source and transitive dependencies, assertion semantics, fixture, runtime inputs, Xcode, OS, device and environment; otherwise rerun. Missing evidence is not reuse. Report executed pass, verified reuse, failed, skipped, not run and blocked separately. Never claim TestFlight approval or completion from source, build, simulator-only or a partial matrix.
