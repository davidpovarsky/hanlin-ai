# MiniApps declares the shared SDK's supported languages

Status: XML/property-list validation and source qualification PASS; native corrected-language acceptance NOT_RUN.

## Exact original observation

Original paired run [45260265662](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45260265662) at `e59256e8325bcdb71c0e683f6b19e7641642aad8` executes `testOriginalPackageAndSavedStateTransferThenRollback()` and fails at its English transfer-completion assertion. The original launch arguments request `AppleLanguages=(en)` and `AppleLocale=en_US`.

The preserved original screenshot and accessibility tree show the completion label `传输完成。你的小程序已准备就绪。`, alongside one installed package. This is byte-for-byte the existing Chinese translation of `Transfer complete. Your mini apps are ready.` in the canonical SDK catalog. The original source assigns that status after successful import through `String(localized:..., bundle: HanlinLocalization.bundle)`. This establishes that the expected status exists in another language; it does not establish the later saved-state, reopen or rollback assertions, which remain NOT_RUN. The whole original method remains FAIL.

## Why only MiniApps host metadata changes

The original main Hanlin and MiniApps source Info.plists both omit `CFBundleLocalizations`. Their resource layouts differ:

- Hanlin owns real `AI_HLY/{en,he,zh-Hans}.lproj/InfoPlist.strings` files. The original successful main build log explicitly copies all three into `AI_Hanlin.app`, in addition to separate SDK bundle copies. Those main-bundle directories already identify the main host languages.
- MiniApps has no host `.lproj` directory. Its UI translations are owned by the shared SDK resource bundle, and the original MiniApps build has no host InfoPlist localization copy. The project development region is `zh-Hans`.

[Original build excerpts and hashes](source-verification.json) preserve this distinction. Main Info.plist, existing main language resources, project settings, and all shared SDK catalogs remain unchanged.

## Smallest host correction

Add only `CFBundleLocalizations = [en, he, zh-Hans]` to `HanlinMiniAppsApp/Info.plist`. These are exactly the languages present in each existing shared SDK translation catalog and the original main host resources. Keep the project/default development language, shared `Bundle.module` lookup, all translations, and the user's language preference unchanged. There is no forced-English locale, runtime language mutation, duplicated string table, mixed-language override or host-specific UI implementation.

Apple's [CFBundleLocalizations reference](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundlelocalizations) identifies this supported-language array; the readable [Core Foundation key reference](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html) documents its use when localized resources are not represented by the application's ordinary main-bundle localization layout. This host declaration is the source-based repair; its actual Foundation/SwiftUI language selection still needs the original native test.

## Validation and next native scope

Python plist parsing passes, the declaration exactly matches the three canonical languages, and removing the six-line insertion restores the prior Info.plist bytes. All prior keys/values, original three paired test methods, acceptance assertions and timeouts are unchanged. Catalog hashes and source-language values are recorded. No native build/test was dispatched by this commit.

The changed metadata affects MiniApps host localization. The original transfer method must be reexecuted; its later import/state/navigation/rollback assertions must actually run before acceptance. The separately corrected shared compact ChatView affects the two consent methods and original main chat UI. The requested paired continuation must retain strict authenticated foreground/Host proof reuse and original three selectors.
