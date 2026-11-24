# Disambiguate the original Xcode application target

The original 45265065184/1 run at ade2f626e37102abde83050c94d524d19e0726bb built the real app and tests, but Xcode generated the UI target path without .app. The original manifest has the valid unit host __TESTROOT__/Debug-iphonesimulator/AI_Hanlin.app and the invalid UI target __TESTROOT__/Debug-iphonesimulator/AI_Hanlin. The original dependency graph lists a target named AI_Hanlin in both the AI_HLY Xcode project and the HanlinSDK package.

original-collision-evidence.json binds the two original dependency-graph log lines and both original generated manifests to the already acquired artifact and its complete member inventory. Nothing was downloaded again. The name collision is established by original output; whether this source repair resolves Xcode's generated UI path still requires native verification.

## Exact source repair

The Xcode executable target is now HanlinApp. Its original target ID, product reference, product AI_Hanlin.app, executable AI_Hanlin, bundle identifier, and module name HanlinApp are retained. Both build configurations pin PRODUCT_NAME = AI_Hanlin explicitly. Two UI TEST_TARGET_NAME references, two container proxies, and six scheme blueprint names point to the unique executable target.

The SDK implementation target/module remains AI_Hanlin. The updater, manifest generator, original project graph verifier, actual app resolver, two RuntimeCore source lookups, and one TestFlight signing-target argument follow the new Xcode name. TestFlight has exactly one textual substitution; all other workflow bytes are identical. Independent Composer proof host targets are unchanged.

The parsed PBX delta contains exactly seven objects, with one scalar field changed in each. No source, resource, linker, extension, or MiniApps phase changes in this commit. The preceding image-ownership repair is preserved, including all original app and test product declarations.

## Verification and limits

- **FAIL before:** the one new original-project identity regression detected the old colliding Xcode name.
- **PASS after:** all 13 narrowly affected local source controls: the new identity regression, the three source/link ownership controls, eight RuntimeCore source/resource controls, and the existing missing-linked-product negative control.
- The missing-linked-product fixture now removes HanlinApplication, the actual single linked image owner, and retains the strict failure expectation. Removing an already unlinked HanlinAgentCore declaration would not exercise the link guard.
- **PASS:** original generate_manifest.py --check and update_project.py --check.
- **PASS:** generated root manifest bytes and complete inventory remain identical: 44 products, 108 targets, 507 original application Swift sources, 18 child manifest inputs, zero local package edges.
- **PASS:** original project and SDK linkage source gates; every unrelated PBX object remains identical.
- **NOT_RUN:** Apple build, regenerated native UI manifest, simulator UI execution, and runtime confirmation after this repair.

The original failed run has 323 passed, 7 failed, and 12 not-run authored invocations after the parent's original-result reconciliation. This packet does not relabel any failure as passed and does not change Calendar, ShareInbox, credential, or tool behavior or assertions. The failed producer remains ineligible for Native publication.

The candidate contains a one-line workflow change. No CLI workflow push was attempted; the parent will integrate and publish through the already authorized connected GitHub exact-tree route.
