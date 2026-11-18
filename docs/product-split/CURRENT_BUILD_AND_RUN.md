# Current Hanlin build and run

This is the current two-product source and validation guide. The historical W1 documents retain their original findings; they are not the current implementation status. Phase 2 and Phase 3 acceptance remains in progress, and release is **NO_GO** until the [release checklist](../continuation-20261117/RELEASE_CHECKLIST.md) is satisfied.

## Native products

| Product | Xcode scheme | Original bundle ID | Entry point |
| --- | --- | --- | --- |
| Hanlin AI | AI_HLY | com.itorah.chavrusachat | AI_HLY/AI_HLY.swift |
| Hanlin MiniApps | HanlinMiniApps | com.itorah.hanlinminiapps | HanlinMiniAppsApp/HanlinMiniAppsApp.swift |

Both targets use iOS/iPadOS 27 and Swift 6. Existing native evidence identifies stable Xcode 27.2 and the iOS 27.2 simulator; a source deployment target is not proof of physical-device compatibility. The main workflow's historical filename contains ios26; it does not mean the current targets build for iOS 26.

Select the intended source revision before opening AI_HLY.xcodeproj. Runtime binary inputs are prepared through the existing pinned NativeScript, Expo and Runtime scripts used by the manual workflows. Do not replace those engines or synthesize packages to satisfy a test.

The two original App Groups are group.com.itorah.chavrusachat and group.com.itorah.shared. The original AI CloudKit and Keychain ownership stays in AI. Preserve these identities when building updates for the owner's existing installation. Compatible provisioning, group assignments and the original required capabilities are necessary for physical installation and distribution.

MiniApps references the existing AI_HLY/Assets.xcassets catalog and original AppIcon in both configurations. Both configurations declare executable-relative lookup of its own Frameworks directory; independent startup after that repair is still under native validation. Native validation checks the built icon/catalog, Mach-O loader paths, embedded original entitlements and independent app launch; source settings alone are insufficient.

## Current navigation and ownership

Hanlin AI exposes Chat and Library. History opens existing conversations; Profile contains original model/provider configuration, Skill Center, package/tool management and diagnostics. Vision and the companion are contextual workspace actions. Library opens the existing Knowledge, Memory, Prompts, Canvas and saved-message surfaces.

The original Composer, transcript and SDK Session/Host remain the chat implementation. Runtime tools that execute in AI continue to run there. An operation needing MiniApps UI uses the existing foreground bridge and returns to the saved origin conversation; the companion does not contain a replacement agent loop.

Hanlin MiniApps owns the original catalog/package UI and runtime presentations. It uses the existing NativeScript, Expo, ScriptUI and native registration paths. Package import uses the actual preview/install/consent workflow. Do not copy the AI SwiftData conversation store into MiniApps.

## Focused native validation

Use the existing manually dispatched workflows with the scope justified by the changed source:

| Workflow / input | Real gate |
| --- | --- |
| build-ios26-unsigned-ipa.yml / exact_test_selector | Selected original full-app native or UI tests |
| build-ios26-unsigned-ipa.yml / phase2_app_with_motion | Recorded remaining app/runtime/Skills/Motion scope |
| validate-app-split.yml / native_test_scope=production_runtimes | Independent companion startup and two actual NativeScript/Expo UI scenarios |
| validate-app-split.yml / paired_product_acceptance=true, paired_test_scope=product_and_share | Original two-app request/return/cancel/transfer and shared-inbox scenarios |
| validate-app-split.yml / audit_release_resources=true | Read-only existing Apple signing/profile/device audit |
| validate-app-split.yml / signed_release_archives=true | Real device archives and local export with existing signing resources |

Use the exact required runtime artifact input from the recorded dispatch, currently 42926628418, rather than an absent release. Preserve the original test selectors, fixture bytes and mandatory independent startup/OS-container checks. Keep one bounded run watcher per run and inspect original result bundles after completion. Reuse passing evidence only for demonstrably unchanged dependencies and retain its actual SHA, platform and scope.

[ACCEPTANCE_REGISTER.json](../continuation-20261117/acceptance/ACCEPTANCE_REGISTER.json) maps the original 30 tasks to evidence. The seven phase reports are provisional until their gates pass. The 278-feature matrix has explicit per-row limits; a file anchor or component assertion is not whole-product acceptance.

## Release and recovery

The earlier two device archives compiled, but Apple export failed because compatible profiles/signing access were unavailable. Bundle registration and ad-hoc simulator signatures do not complete that gate. Live model/tool/persistence acceptance and an accessible physical device also remain distinct obligations.

Use the existing transfer snapshot, journal, recovery and guarded rollback paths described in the release checklist. Preserve newer writes when rollback would lose data. No production user migration, main merge or TestFlight upload has occurred in this continuation.
