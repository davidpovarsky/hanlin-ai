# Original catalog locale review — 25 November 2026

## Observed evidence

The complete original-app 4b772b5a native run finished with 23 selected tests:
16 PASS, 7 FAIL, 0 SKIP. Its three shared picker tests passed. This is not a full
native acceptance success.

The Hebrew picker image F0F60F1C-442B-45ED-B1CB-6E4D56C53B3B.png (SHA256
3f4818534851541d83f3759da2e14ec4eec0b966bf069b916b504d430d75f332) was visually
reviewed. Its native editing sheet shows readable RTL layout, reorder controls,
favorites controls and one confirmation. The original catalog behind the sheet
still says Apps and Edit in English.

Source inspection confirms two causes in NativeAppsCatalogView.swift: the Apps
title has no entry in HanlinLocalization, and the conditional plain Button title
is a verbatim string rather than a key resolved through that resource bundle.

## Change and verification scope

The catalog now uses the existing semantic mini-apps title
hanlin.morph.miniAppsTitle (Mini Apps / יישומים קטנים) and the existing localized
Edit/Done control keys 编辑 and 完成 (עריכה / סיום). No localization resource,
dependency lock, shared package source, runtime, request, result or callback code
changed. The edit button receives an accessibility identifier; its accessible
label remains the localized human-facing text.

The existing English/Hebrew real-app preferences test also verifies the original
catalog title, Edit-to-Done-to-Edit transitions and captures the localized catalog
before opening the preferences sheet. All prior preferences assertions remain.
The e1a25038 native run remains frozen and is not evidence for this later source
change. Actual incremental build and affected native UI execution are required.

The original Anytype SDK source owner verified that this AI_HLY app view lies
outside the three package closures compiled into its current framework:
HanlinAgentSDK, HanlinPlatform and HanlinPresentation. Those package trees remain
byte-for-byte unchanged by this patch.
