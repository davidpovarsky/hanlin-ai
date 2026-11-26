# Standalone Shortcuts foreground ownership and localization

## Exact source and scope

This implementation belongs to SCRIPTABLE05 (Asana 1220917834527539), following the user's two-wave execution authorization and the root's explicit scope decision. Source commit: **a6eaf6ee77fbc0a48e9997b434dc28d2c15b916d**, based on **9819697c1792119a6a93b492d12abad7b3330c93**, with the separate native import correction **ce83512d8f2ce97f8164742c2211fafbc53e4f99**, initial foreground implementation **e34a86a79310d310d5635faff65d262f9c85dced**, test-only canonical type qualification **f6b577bb0442fecd2b349bb8fbe8db96767b63d7**, terminal settlement **559f77b04ff701c4bc50669e25630b2ccbbc0882**, hidden draining ownership **82673cef95c547c1b1f27dff3be63bbb4e8fe2a5**, and container lifetime delegation **a6eaf6ee77fbc0a48e9997b434dc28d2c15b916d** retained as separate commits.

The new standalone MiniApps intent supports the OS-selected background or immediate foreground mode. Its actual `systemContext.currentMode` controls the delivery envelope and original provider's UI permission. Merely being able to continue in the foreground never opens the app or prompts a background invocation. The shipped Run Script Action declarations and identifiers remain byte-equivalent to source 981; their three source hashes are in `source-preservation.json`.

No native/Shortcuts acceptance is claimed by this source receipt. The native owner has the original routes and selectors below.

## Authorized feature reconciliation

| Task05 requirement | Actual route and boundary |
| --- | --- |
| Saved action selection and existing intent compatibility | Preserve the original entity identity, enabled-package/generation/entrypoint admission, signed/prepared package model, and both existing delivery=nil intents. The new intent uses the saved prepared action. |
| Dictionary/List and nested values | Existing `HanlinShortcutValueCodec` accepts ordinary JSON text or a typed .json IntentFile; result files preserve text, JSON, or binary data. Native AppIntents does not declare a generic arbitrary Dictionary parameter. This change does not invent one or encode the internal tagged value format as public JSON. |
| Inline code, only where compatible | The authorized task makes inline input conditional and prefers a saved prepared action. An arbitrary raw JS parameter cannot satisfy the current compiler/manifest/capability/generation admission contract. No raw-code engine or parallel interpreter is introduced. Canonical Studio/authoring can prepare and install a package, whose saved action then uses the existing intent. |
| Open When Run | The newly introduced standalone intent changes its metadata from background + dynamic to background + immediate. The OS chooses its actual mode; foreground delivery presents the invocation's original provider through the existing standalone scene container. Default/persistence of the OS toggle, saved/new Shortcut behavior, and foreground delivery are real OS acceptance gates. |
| Home Screen | Use Apple's saved Shortcut > Details > Add to Home Screen route. Existing trusted mailbox URLs remain expiring invocation handoffs; they are not permanent action URLs. OS Home Screen launch/chaining remains a native probe. |
| Snippets, refresh, wait | Existing receipt-backed snippet, refresh and wait intents remain the source of status/result. Their static labels now use the same canonical host localization table. A durable success receipt is not changed by later UI dismissal. |
| Hebrew/RTL and localization | 42 new keys are projected into the host's AppIntents table in en/he/zh-Hans. All original 18 host keys and original 1,252 canonical catalog entries retain their complete values. Real Shortcuts rendering, accessibility and RTL layout remain OS/UI gates. |
| Background cancellation/long-running/progress | The original executor owns a lease before OS preparation suspends, renews it through preparation and runtime execution, and records the actual terminal outcome. The existing public cancellation/LongRunningIntent APIs remain; a closed or cancelled invocation's provider cannot update another invocation's Progress. |

## Existing record and execution ownership

`enqueueAndClaim` validates and writes the existing command/receipt/lease record in one existing store transaction. It adds no persistent schema field. An exact duplicate retains its command, lease and terminal receipt; a conflicting duplicate fails. The command returned to the handler is the exact persisted envelope, including the existing date encoding.

The original UUID executor route retains its retryable `HanlinInvocationNotStarted` behavior for legacy queued actions. The new command-taking overload turns an unstarted live intent admission failure into its terminal unavailable-host receipt; it cannot leave work queued after the intent has ended. Loss of the process still uses the original expired-lease, non-idempotent `deferred/interruptedOutcomeUnknown` behavior rather than replay.

The foreground provider is invocation-local and never overwrites the active scene's handler. The existing root scene owns an exact-ID presentation slot; occupied UI rejects only the new intent. Its existing foreground drain observes the same lease and cannot steal it. There is no new blanket source=shortcuts skip. The original headless filter is unchanged, and legacy delivery=nil queue regression coverage remains explicit.

Closing an owned running presentation requests cancellation; the original executor drains the handler and settles its durable receipt. Only matching-ID dismissal can close that UI. The owner retains the original fresh-process product-transfer boundary because the child provider can touch the same product storage. Successful UI can remain visible after the result is returned; its closed progress reporter rejects late callbacks. Independent review of e34 found that pre-terminal cleanup of a successful action without a surface could race the executor with a cancellation request. Commit 559 moves owned foreground cleanup after the actual executor outcome, preserves true user/OS cancellation, and adds a real owner/store/executor regression for non-surface success. On receipt-write failure, the drained executor still permits explicit owned provider teardown; it does not fabricate a terminal receipt. Follow-up independent review found that clearing the presentation slot before running cancellation drained could lose the native cleanup owner. Commit 826 retains a hidden, dismissal-requested slot until actual executor settlement; a late launch cannot display it again, and terminal settlement explicitly closes the original native session/provider. Commit a6 delegates container disappearance to the same lifetime owner. A real original NativeScript running-close regression checks the retained owner, cancellation receipt, controller release, and zero remaining original windows.

## Public Apple semantics used

- [AppIntent supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes): background + immediate allows system-selected foreground; background + dynamic prefers background.
- [ForegroundMode.immediate](https://developer.apple.com/documentation/appintents/intentmodes/foregroundmode/immediate): foreground transition follows parameter resolution.
- [ForegroundMode.dynamic](https://developer.apple.com/documentation/appintents/intentmodes/foregroundmode/dynamic): a dynamic intent needs an explicit foreground continuation request to transition.
- [IntentModes.Current](https://developer.apple.com/documentation/appintents/intentmodes/current): inspect the current foreground/background mode.
- [canContinueInForeground](https://developer.apple.com/documentation/appintents/intentmodes/current/cancontinueinforeground): indicates that transition is possible in the current context; it is not a user request.
- [WWDC25: Explore new advances in App Intents](https://developer.apple.com/videos/play/wwdc2025/275/), supported-modes/Open When Run segment around 18:15–19:50.
- [Apple Shortcuts: Add a shortcut to the Home Screen](https://support.apple.com/en-ng/guide/shortcuts/apd735880972/ios).

These sources establish API semantics; they do not substitute for current app metadata extraction or an actual saved Shortcut run.

## Exact checks and retained failures

- `swift-syntax.json`: Linux Swift 6.4.3 syntax checks for 12 affected Swift files, with exact per-file hashes. Prior passes were reused only for byte-identical sources; terminal-settlement and native test qualification changes have their own current hashes. This does not typecheck Apple imports or prove native execution.
- `original-localization-install-tests-r2.log.json`: the original `Scripts.SDK.tests.test_app_intents_install.AppIntentsHostResourceInstallTests` passed 2/2 using the correct chatgpt-agent environment.
- `original-localization-install-tests.log.json`: the initial attempt is retained separately. Its uid-only execution inherited root HOME and failed to write the Swift/Clang cache; no product assertion was weakened.
- `localization-generator-check.log.json`: canonical `generate_app_intents_resources.py --check` passed with 60 keys.
- `source-preservation.json`: all legacy intent source bytes and original catalog entries preserved; `git diff --check` passed.
- The original native981 package build failed before tests with a missing import in `HanlinWidgetLastSuccessfulRender.swift`. The error type really exists in HanlinScriptContracts, already a target dependency. Separate ce835 adds only that import. The original failure remains at `/Users/m1/builds/hanlin-two-wave-root-20261126/platform-native-build-9819697c-r1.json`; no native pass is inferred from the correction. The ce835 retry compiled past that production error, then failed in the parameterized render test macro on unqualified HanlinWidgetEngine. The canonical nominal type and an exported same-named alias are both imported. Separate f6b qualifies all three occurrences with HanlinPlatformContracts, preserving both engine cases and every assertion; the native owner retains the second failure in validation/platform-ce83512d/build-r2/original-package-build-for-testing.log.

## Original native execution inventory

| Original route | Selector | Definitions | Invocations | Scope |
| --- | --- | ---: | ---: | --- |
| HanlinPlatform-Package on iOS | HanlinScriptExtensionsTests/HanlinInvocationQueueTests | 19 | 19 | 14 original + 5 new; atomic ownership, duplicates, lease loss, cancellation and legacy retries |
| HanlinMiniApps application test host | HanlinMiniAppsTests/NativeScriptShortcutConcurrencyTests | 5 | 5 | 2 original + 3 new; actual original engine/provider/controller/storage, occupied foreground, running-close cleanup |
| HanlinMiniApps application test host | HanlinMiniAppsTests/MiniAppsShortcutIntentTests | 4 | 6 | Actual host localization in 3 locales, progress isolation, matching terminal result, terminal-only no-surface cleanup |

There are **12 added definitions/14 added invocations**, and **28 definitions/30 invocations** across the affected full suites. The package's previous 59-case inventory is separate and remains scoped to its recorded source. The package route accounts for 19 definitions/cases; MiniApps accounts for 9 definitions/11 cases. No new Hanlin application test definition is added. The root still runs the canonical affected Hanlin suite planner for the integrated source. No native job was launched by this lane. Add the new MiniApps test file through the canonical project generator before the application test build.

Required OS acceptance remains: Shortcuts new/saved Open When Run toggle default/persistence, background without prompt/UI, real foreground original-engine presentation/dismissal, long-running cancellation and permission refusal, Dictionary/List/file chaining, saved Home Screen launch, snippets/wait, Hebrew/RTL and accessibility. Retain actual observed receipts and matching source/SDK/toolchain evidence.

Independent final source review is retained in `independent-foreground-review-a6eaf6ee.json`. It found no further blocking issue in the bounded paths, preserved all 19 protected source-owner hashes and the existing 7 IDs/3 app delegations, and explicitly leaves native/OS/device gates open. It does not replace those gates.

## Canonical SDK and Host input impact

`sdk-input-impact.json` classifies the exact changed files against the original `Scripts/MiniApps/stage-sdk.mjs` source-input declarations. Seven changed production files are direct recursive inputs: three ScriptingPlatform files and four HanlinScriptExtensions files, including the ce835 import correction. They change the SDK input fingerprint even though JavaScript facades, original engine package locks and compiler packages remain unchanged.

The standalone intent, native localization resources/generator and tests have native/build effects; they are outside those direct SDK source roots. Canonical inventory regeneration can add further indirect SDK input changes. The native owner must qualify the final integrated producer/fingerprint; existing 981 Host/gallery receipts remain exact981 evidence.

## Generic broker 17 exposure audit

At source 981, the 17 methods declared by `AI_HLY/Downstream/HostServices/System/HanlinSystemServicesBroker.swift` are explicitly qualified by canonical `source-inventory.json#/systemServices` and `extension-reachability.json#/systemServices`: declarations do not establish a generic NativeScript/Expo binding, OS availability, permission grant or UI permission. The original stage-sdk engine capability lists do not advertise these 17 as bound runtime APIs.

No false runtime capability advertisement was found in the inspected source-derived exported metadata. This audit did not inspect the newly produced 981 SDK artifact bytes. The original NativeScript native APIs and actual ScriptWidget providers are separate paths and are not classified as absent. See `broker-exposure.json` for the exact source hash, method list and qualifications.
