# SDK18 built consumers and produced packages

This is an independently checked identity checkpoint on source f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51. It does not certify completion of the running application acceptance suite.

## Actual built consumers

The original native-owner receipt records both completed consumer builds, both original deep/strict signature checks, and five embedded Host archives. All five bind Host SHA ce240d8d4083a2babfa3827fd12f93e0ad469b45c5f7055a259fcb8babe1881f, manifest 1ca059acbc56b0d8d33f3d678c5023fd5aff26c744ac1e5412c3b1663529dfcd, and authoring module fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9. SDK input identity is ca69ce053b0d82c258ffd29f1e0ec07eb77da9f8f6893ffe1a68eecdbe02c7ca.

All 11 transferred consumer members (227,531 bytes) were independently read and checked. Both notification extension Info files, original Mach-O entitlement observations, executables and implementation debug dylibs are bound. Simulator ad-hoc codesign entitlements are empty; the actual simulator entitlement section is explicitly identified. The two original ios_system main-bundle dictionaries match the Git source and both original validators report 23 approved commands and no unexpected commands.

The actual Worklets object is retained and independently read: offset 4448 contains the unquoted null-terminated 0.13.0. Parsing the complete response argument yields exactly -DWORKLETS_VERSION=0.13.0. The response file quotes the whole shell argument, which does not put quotes in the macro value. This distinguishes the repaired native bytes from the prior quoted/stale version. Runtime feature results remain separate.

## Actual produced packages

All 11 producer packet members (4,193,912 bytes) were checked. The five archives contain 109 unique members in total; every member was read and hashed. All recorded compiled hashes match. Fifty-five source bindings, including all retained current Modular and SDK-only source files, match the exact Git commit. The two independent examples and Modular build reports bind the same SDK18 manifest with zero diagnostics. Expo reports strict checking including dependency declarations; the NativeScript report honestly retains its actual skipLibCheck: true setting.

| Archive | Bytes | Role |
| --- | ---: | --- |
| ModularTextSearch.hanlinExpo | 2,203,502 | Current original Modular source and native presentations |
| SDKOnlyDepartureBudget.hanlinExpo | 1,956,755 | Independent Expo SDK-only example |
| SDKOnlyTableShare.hanlinNativeScript | 12,933 | Independent NativeScript SDK-only example |
| NativeScriptAuthoringExample.hanlinNativeScript | 4,400 | Valid original authoring example |
| MiniAppTypeError.hanlinNativeScript | 4,400 | Source-bearing negative input for diagnostics and repair |

The valid and negative authoring archives differ only at source/index.ts. The negative retains the actual string-to-number error and the original recorded source hash, so original validation reports both TS2322 at line 1, column 14 and MINIAPP_SOURCE_CHANGED. Its full archive SHA is c5006389c6b1e09209d173ccad8f6397cb06c8cfaf7a395233827822c1b181a9. The provenance field invalidArchiveSHA256 refers to a different deliberately non-ZIP InvalidMiniApp.zip; it is not the hash of this source-bearing archive.

## Boundaries and retained evidence

The original native observations are unchanged. This independent check used Oracle bytes and exact Git source only: no native query, build, test, generator or compiler rerun. It does not independently reread full app binaries from the Mac. Original 25/27 runtime results, installation/repair receipts, OS notification delivery and physical-device observations remain separately recorded. The running original 25-case sequence has reported failures; this checkpoint is not a full application PASS.

verification.json gives precise identities and dispositions; package-members.json covers all five archives. raw-consumers/ and raw-producer/ retain the actual small source receipts. Exact archive locations and hashes are in retained-package-archives.json; the archives themselves remain in the immutable transfer packet for user delivery.
