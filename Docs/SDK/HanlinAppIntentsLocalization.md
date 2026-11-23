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
selects that documented default-capable form. This is a source correction awaiting the
next original Apple build, not a claim that a Linux syntax check proves metadata export.

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
Latest native attempt: [45224582718](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45224582718)
passed RuntimeCore preflight, native export and SwiftPM resolution, then failed AppIntents
metadata export. All 32 selected application/unit/UI scopes remain NOT_RUN in that attempt.

Primary API references:
- [AppEntity localized type representation](https://developer.apple.com/documentation/appintents/defining-app-entities-for-your-custom-data-types)
- [Default BundleDescription initializer](https://developer.apple.com/documentation/foundation/localizedstringresource/init(_:table:locale:bundle:comment:)-69k32)
- [Explicit Bundle initializer](https://developer.apple.com/documentation/foundation/localizedstringresource/init(_:table:locale:bundle:comment:)-8o153)
