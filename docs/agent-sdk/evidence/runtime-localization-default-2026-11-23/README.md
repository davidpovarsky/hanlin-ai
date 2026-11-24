# Runtime localization validator default follows its canonical resource

The dependency-update workflow invokes validate-runtime-localization.mjs with no arguments. Its old default pointed to the removed app-owned RuntimeLocalizable.xcstrings. Only that default literal now points to the original catalog in HanlinLocalization.

The exact no-argument usage ran once on Oracle against canonical d49a4fd4115b8335105d2991bf74ab4d7f6aad2d source/catalog bytes and passed:196 RuntimeL10n keys, en/he/zh-Hans. Source root, namespace, key discovery and validation behavior are unchanged. The before/after script comparison proves the default literal is the sole code change.

This is harness maintenance after the product freeze. The existing Hanlin native preflight already supplies this canonical catalog explicitly, so its pending run remains source-valid and does not need redispatch for this maintenance change. No workflow edit, native build or CI dispatch was performed.
