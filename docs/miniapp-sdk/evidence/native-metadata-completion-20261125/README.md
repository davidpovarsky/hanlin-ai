# NativeScript Core metadata completion

This candidate takes only original donor `8538eea609ba85d7788c38fab04a26f523deba5c` onto frozen Wave2 `aec179de037c439566c1699777dd4cfb492de860`. The production change selects the native frameworks that original NativeScript Core declares, and requires `TNSLabel` and `NSCCrypto` in generated metadata. It preserves the upstream generator, all existing required names, compiler diagnostics and native framework binaries.

The retained original six-case run remains **3 passed, 3 failed, 0 skipped**. Its SDK-only NativeScript failure was a missing metadata class, despite the compiled framework exporting that class. The later original owner builds genuinely generated and installed metadata containing both missing classes in both applications. Their exact source is recorded separately; this is component build evidence, not a combined Wave2 app build or a runtime acceptance claim.

`qualification.json` binds the exact source and evidence. All 16 candidate native input hashes equal the retained prepared catalog. All 15 native framework ZIPs and binary/slice descriptors are unchanged from the earlier catalog. All 20 retained native/support ZIP checksums were read and matched the new original catalog. The two changed support archives are recorded explicitly. The catalog is still **prepared**, not a published SDK release.

The original test timing and diagnostic-finalization donors are intentionally absent from this production candidate. No native build, simulator execution, engine rebuild or foreign mutation was performed by this integration lane. Final-source Host documentation and ZIP preparation, the combined application build, original runtime UI, and publication remain separate required work.
