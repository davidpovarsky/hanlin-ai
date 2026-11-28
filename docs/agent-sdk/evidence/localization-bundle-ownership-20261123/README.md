# Canonical localization across embedded SwiftPM bundle copies

The full app build in45246711373 includes the same original HanlinSDK_HanlinLocalization.bundle in the app, share extension, translation extension and widget extension. The retained original Xcode copy commands bind these locations to the same build-product source. Runtime preparation removes only test bundles and test frameworks; it retains the application extensions.

Source inspection found that the next validator, Scripts/CI/validate_chat_localization.py, also required exactly one matching bundle path. A realistic app/framework/two-extension fixture reproduced its rejection before this repair. This is a source/fixture finding made while45256955142 was still running; it is not a claim that that run had already reached or failed localization validation.

The validator now reuses the unchanged canonical SDK module_bundle and bundle_inventory functions from3137a54b. Every embedded copy must have the same permitted bundle identity and equal complete inventories of entry paths/kinds/sizes/hashes/safe links. Only then is one copy used for the original source-to-packaged translation checks. Direct resource-bundle and historical app-root table inputs retain their original behavior.

No localization values, resource packaging, Swift application code, selected test source or original translation predicates changed. Missing keys, damaged text, duplicate source JSON keys, language/format mismatch and packaged values differing from the canonical source remain failures. Equal stale translations cannot pass.

- Before: the new valid multicopy fixture FAILed the original single-path assumption.
- After: six affected controls PASS: equal copies, stale extension translation, altered non-table entry, two distinct bundle identities, equal-but-wrong canonical translations, and direct bundle input.
- Independent release-host reviewer inspected the diff and retained evidence without rerunning controls; no guard regression found.
- The shared SDK inventory helper is byte-identical to its already-reviewed/tested3137 implementation. Its eight controls were not replayed.
- Actual post-copy equality and native locale execution remain NOT_RUN until a run containing this repair reaches those gates.

The original source job log remains under build/sdk-require-continuation-20261123/terminal/native-job.log, SHA25636ec059cdadb68070c67db73ddc2bf935c3a475bddef228204aa16cf538f735b. The selected original command lines are retained byte-for-byte, with line numbers recorded separately.
