# ScriptWidget: why SDK18 records two revisions

This note preserves the completed read-only trace of exact consumer/producer source `f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51` and its immutable SDK18 packet. It makes no new native or current-internet verification claim.

The retained resolver selected `4da256d58247bbafb9a5cd443a285250b97b3c4b`. Both `versions.scriptwidget.revision` and `sourceUpdates.scriptWidgetCommit` record it; `changedNativeSources` is empty. The SDK's comma-separated value also contains `68f04194f00222558c44d5a832e7617a96f62574` because the SDK generator collects every manifest row's base `commit`, including two authored Hanlin adapters.

| Source group | Rows | Recorded revision |
|---|---:|---|
| Original renderer components | 41 | 4da256d5… |
| Original services and core | 55 | 4da256d5… |
| Original native controls | 2 | 4da256d5… |
| Original support resources | 3 | 4da256d5… |
| Authored host-adapter derivation | 2 | 68f04194…; latest upstream contract4da256d5… |

The two historical rows are `HanlinScriptWidgetRuntime.swift` in HanlinScriptExtensions and `prepare-widget.js` in HanlinWidgetCompiler. Both explicitly have `sourceRole: host-adapter`, `latestUpstreamContract.identity.commit:4da256d5…` and `changed:true`. They intentionally preserve their derivation history instead of being replaced by an unrelated complete upstream app runtime. The separate original service implementation, `HanlinScriptWidgetOriginal/Original/Widget/Runtime/ScriptWidgetRuntime.swift`, records the selected4da revision.

[The original refresh logic](https://github.com/davidpovarsky/hanlin-ai/blob/f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51/Scripts/MiniApps/refresh-original-sources.mjs) selects/fetches the immutable revision at219–238, records adapter contracts and continues at256–260, and advances ordinary original rows' commits at282–288 even when content is unchanged. Thus the historical revision is specifically adapter derivation provenance, not an unchanged-original-file shortcut.

[SDK staging](https://github.com/davidpovarsky/hanlin-ai/blob/f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51/Scripts/MiniApps/stage-sdk.mjs) at261–262 aggregates all ScriptWidget row commits without filtering by source role;277 places their joined value in `packageVersions`, and298 copies it to `upstream.scriptwidget`.

## Verified boundary

All103 local Git file SHA256 values match the source manifest. All31 rows claimed byte-identical match their recorded original Git blob IDs. The other70 original rows are explicitly adapted; the remaining2 are host adapters. All6 original API catalog/license files match their provenance hashes and use4da. The actual SDK18 input manifest binds the exact resolver, source manifest, catalog and upstream-resolution hashes.

This identifies no stale original-source group from the mixed revision string. It does not independently re-download all original source bytes or replay the70 historical adaptations. Both adapter contract records say the upstream contract changed, so their metadata alone is not proof of every runtime behavior. Current native/runtime acceptance remains the separate authority.

[provenance-analysis.json](provenance-analysis.json) retains full revisions, paths, hashes, group counts, source lines and the exact limits. No source fix or SDK regeneration was performed for this explanation.
