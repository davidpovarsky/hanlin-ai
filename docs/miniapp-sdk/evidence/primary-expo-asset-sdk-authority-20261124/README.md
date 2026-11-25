# ExpoAsset SDK and native declaration companion

This extends source commit `7865249ad98f7c9286a15e1c022aba0fabde91b6` after root review found a concrete authoring-metadata gap. SDK7 already contains original ExpoAsset package and declaration bytes, but its twenty direct Expo package keys omit expo-asset. Those keys drive both `get_miniapp_sdk` resources and canonical TypeScript/Metro resolution, so an authored direct import could select another installed copy.

The companion promotes the already locked `expo-asset@58.0.21` to a direct tooling dependency and updates only the root npm lock dependency entry. All existing nonroot package records, original ExpoAsset source/declaration bytes and every other lock byte stay unchanged. The existing installer will capture the new package/lock input identity.

The SDK producer checks native and authoring ExpoAsset version parity and advertises the module in `hostContract.plugins`. Native admission accepts the exact embedded ExpoAsset version from generated `HanlinMiniAppHostVersions.expoAssetVersion`. Other version/plugin checks retain their semantics, including unknown-plugin rejection. A focused existing analyzer test covers the actual version, a different version and an unknown plugin. The upstream-version regression checks the generated constant too.

## Generation actually performed

Only the existing exported `generatedHostVersions` helper was invoked with retained original resolution and the verified current ExpoAsset native/npm lock entry. Its real command, UTC time, Node version, inputs and output are retained in `generator-observation.json`. The generated file changes by one constant; all former bytes are identical. This invocation performs no npm resolution, network access, native compilation or tests.

The root unified package manifest generator, original npm installation/preparation, native source producer, SDK packing, native artifact export and Apple consumer/runtime verification remain owned by the main/native lanes. The initial ExpoAsset receipt stays historical evidence for its original commit. This companion supersedes the relevant current resolver/test hashes with the complete SDK surface.

## Remaining actual verification

The next prepared SDK must contain twenty-one direct Expo package keys, including `expo-asset: 58.0.21`, the original declaration entry `expo/node_modules/expo-asset/build/index.d.ts` and the matching native plugin declaration. The actual SDK/Host identities must be reconciled after preparation. The original three failed Expo runtime cases remain failed until their original assertions pass on corrected execution.

No native compilation or test execution is claimed by this source companion.
