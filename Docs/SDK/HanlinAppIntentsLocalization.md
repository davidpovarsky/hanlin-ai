# Shared AppIntents localization

The original AppIntent and AppEntity implementations remain in HanlinScriptingWidgets and AI_Hanlin.
Apple's metadata extractor accepts .main for static package declarations but rejects a
resource bundle URL in those declarations. Twenty metadata resources use the namespaced
HanlinAppIntents table in the executable. The original runtime dialog and all other
SDK text still use HanlinLocalization.bundle.

Scripts/SDK/generate_app_intents_resources.py derives the eighteen required keys for
English, Hebrew and Simplified Chinese from the one canonical
HanlinLocalization/Resources/Localizable.xcstrings catalog. Missing original intent labels were completed in that catalog; all existing entries are unchanged.
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

Failure source: [45177292887](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45177292887).
Apple compile and the 28 previously blocked selectors remain NOT_RUN until the corrected
native continuation finishes; source-generation checks alone do not qualify them.
