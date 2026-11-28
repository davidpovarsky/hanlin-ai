# Apple qualification contract — native typed List input

Status at the R2 source-review boundary: **NOT_RUN**. Execution belongs to the existing Mac/native owner, after root binds and integrates the reviewed source. This document is not authorization to replace an active native checkout or start a parallel job.

## 1. Public declaration admission, if it resolves an early compiler risk

`NativeListParameterAdmission.swift` (retained losslessly as `NativeListParameterAdmission.swift.gz`) is an evidence-only typecheck input, not a product file or a runtime test. It copies the candidate's original/new parameter declarations, complete conditional summary and AppEnum. For SDK-only compilation, the existing domain `action` entity is explicitly replaced by a String and the type uses a trivial nonexecuted AppIntent result. The probe therefore qualifies only the four optional Array parameter types and the conditional-summary syntax. It does not qualify the actual entity, LongRunning/Cancellable behavior, emitted shipping action metadata, saved shortcuts, decoder or app execution.

The native owner may use the already admitted installed Swift/iPhoneSimulator SDK frontend typecheck pattern, strict concurrency and existing 60-second probe bound. Do not add private protocols, global shims, fake Hanlin modules or widened timeouts. Retain exact source/toolchain/SDK/command/stdout/stderr/exit. If the actual target is built directly, this separate probe can be omitted.

## 2. Execute the real shared codec tests

Use the unchanged package, dependency resolution and existing native gate/controller conventions. The focused command from repository root is:

```sh
swift test --package-path Packages/HanlinPlatform --filter '(shortcutDictionaryAndListRetainStructureAndExactNumbers|shortcutJSONAcceptsScalarValuesWithoutDoubleEncoding|shortcutJSONRejectsMalformedOrLossyInput|shortcutTextRemainsTextAndBinaryOutputRequiresAFile|shortcutNativeTextListPreservesOrderAndExactUnicodeBytes|shortcutNativeIntegerListRetainsValuesBeyondBinary64Precision|shortcutNativeBooleanListDoesNotCoerceToNumbersOrText|shortcutNativeNumberListRetainsFiniteBinary64TypesAndBits|shortcutNativeNumberListRejectsNonfiniteItems|shortcutNativeEmptyListsRemainArrays)'
```

The expected declaration set is the four old methods plus six new methods in `HanlinPlatformContractsTests`. Preserve the original parameterized cases in both JSON tests. Reconcile actual discovery/start/terminal identities; an exit code or a partial name match alone is insufficient. Do not relabel a focused run as the unfiltered package gate. No test deadline was changed or introduced by this source candidate.

## 3. Compile the actual standalone target and emitted AppIntents metadata

Use the existing `HanlinMiniApps` scheme/build-for-testing or original bound test descriptor route, with its actual supported destination and budgets. The relevant app test selector is:

```text
HanlinMiniAppsTests/MiniAppsShortcutIntentTests
```

It contains four unchanged original methods, four new methods, the existing unchanged command helper, and the existing/new three-locale parameterization. Compile the actual intent and shared codec, not only the declaration probe.

Before crediting metadata compatibility, inspect actual emitted metadata for `HanlinRunMiniAppShortcutIntent` and compare the five original parameter identifiers and their values/types/defaults:

| Identifier | Existing type/default |
| --- | --- |
| `action` | Existing `HanlinScriptActionEntity`, unchanged |
| `inputType` | Existing AppEnum, `.text` default; raw `text`, `json`, `jsonFile` retained |
| `input` | String, empty default |
| `jsonFile` | Optional IntentFile, JSON content type |
| `allowLongRunning` | Bool, false default |

The only new parameters are optional `textItems: [String]?`, `integerItems: [Int]?`, `numberItems: [Double]?`, and `booleanItems: [Bool]?`; the only new enum cases are `textList`, `integerList`, `numberList`, `booleanList`. Old default-summary content is preserved in `DefaultCase`. Existing modes, target, title, output IntentFile and snippet identity must remain intact.

Actual locale/resource tests must read the compiled host bundle. Parsing `.xcstrings` on Linux establishes source consistency only.

## 4. Explicit remaining OS obligations

No new OS selector or fixture is part of this patch. Real Shortcuts still needs to verify selecting each supported native type, empty/nonempty input, values arriving with the expected types, saving/reopening, passing the result to a following action, and running previously saved text/JSON/file actions. Mixed/nested/null input retains the existing JSON route; arbitrary native Dictionary/Any/UnionValue support is not claimed. Existing cancellation/progress/provider/output acceptance remains applicable with an exact current-input binding; source preservation alone does not mark it executed.

## Source admission

The current installed public SDK packet is `installed-appintents-public-contract-27-24fd1e20`. Its assessment SHA256 is `c13b6adfb81ba3e4ebcb7ae80f93dd8537e25fc97f6c319bf5355691096e2bd9`; the Simulator AppIntents interface SHA256 is `21e7c17d0a1629940444f303bb6ea8c77f88a4fd9c7f0a5009851f44e412205f`. Simulator/device declarations agree for the supported primitive/Array/Optional forms. Neither the packet nor this probe establishes arbitrary Dictionary or heterogeneous union parameters.
