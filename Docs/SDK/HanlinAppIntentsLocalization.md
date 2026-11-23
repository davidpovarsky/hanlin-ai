# Shared AppIntents localization

The original AppIntent and AppEntity implementations remain in HanlinScriptingWidgets and AI_Hanlin.
Twenty metadata resources use the namespaced HanlinAppIntents table in the executable.
They use LocalizedStringResource(key, table: "HanlinAppIntents"), whose default bundle
is main. This is the initializer form used by Apple's AppEntity documentation.
The original runtime dialog and all other SDK text still use HanlinLocalization.bundle.

The explicit bundle: .main candidate was rejected by Xcode 27.2's metadata extractor
in run 45224582718 even though both original package source files were recompiled.
Foundation exposes both Bundle and BundleDescription initializer overloads; only the
BundleDescription overload supplies the default bundle. Omitting the explicit argument
selects that documented default-capable form. Actual run 45230545076 subsequently
exported Metadata.appintents for the shared HanlinScriptingWidgets target, original
HanlinScriptingWidgetsHost extension and shared AI_Hanlin target. Retained original
constant metadata confirms the BundleDescription overload and HanlinAppIntents table.
The final application build then failed in separate NativeScript libssh2 discovery;
runtime locale acceptance remains NOT_RUN.

Scripts/SDK/generate_app_intents_resources.py derives the eighteen required keys for
English, Hebrew and Simplified Chinese from the one canonical
HanlinLocalization/Resources/Localizable.xcstrings catalog. Missing original intent labels
were completed in that catalog; all 1,118 previously existing entries are unchanged.
The generated Packages/HanlinWidgetSDK/HostResources/HanlinAppIntents.xcstrings
is a build projection, not a second editable translation source.

A host adopting HanlinWidgetUI or the full HanlinApplication must reference this one
generated catalog in Copy Bundle Resources for its application and every extension
that includes HanlinWidgetIntentsPackage. Use the HanlinAppIntents table name;
do not rename it to the host's Localizable table. This avoids collisions with host
labels. The SDK implementation and its intent identities remain shared.
Hanlin's canonical project generator installs both references. Updating the SDK must
regenerate/check the table and retain those references.

Commands: python3 Scripts/SDK/generate_app_intents_resources.py, then
python3 Scripts/SDK/update_project.py. Both commands accept --check.

The original AppIntentsPackage registration in the application and widget entry
points is retained. The native application test
HanlinApplicationSystemIntegrationTests.widgetIntentMetadataLoadsTheOriginalHostTranslations
checks deferred title localization and the actual app/extension bundles in all three
languages. It is not claimed as passed before Apple execution.

Original failure: [45177292887](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45177292887).
Latest completed native attempt: [45230545076](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076).
Three original AppIntents target exports PASS; complete app/test build FAIL at subsequent
NativeScript libssh2 discovery. All 32 selected scopes (310 authored methods / 342 expected
invocations) remain NOT_RUN. [Authenticated original evidence](../../docs/agent-sdk/evidence/appintents-export-libssh2-45230545076/README.md).

Primary API references:
- [AppEntity localized type representation](https://developer.apple.com/documentation/appintents/defining-app-entities-for-your-custom-data-types)
- [Default BundleDescription initializer](https://developer.apple.com/documentation/foundation/localizedstringresource/init(_:table:locale:bundle:comment:)-69k32)
- [Explicit Bundle initializer](https://developer.apple.com/documentation/foundation/localizedstringresource/init(_:table:locale:bundle:comment:)-8o153)
