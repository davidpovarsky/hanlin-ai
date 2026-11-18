# Actual NativeScript and Expo inside the companion

The original Hanlin AI engine tests intentionally open the original runtime component using the simulator-only acceptance input (Debug, or Release with HANLIN_TESTING). They are valid engine/Host component evidence, but do not establish importing/running those packages in the separately installed MiniApps product.

The new production_runtimes scope builds and launches the real com.itorah.hanlinminiapps target on an owned iPad simulator. It stages only the two original archive files in that app's real Documents container, with byte hashes. The UI must use the original catalog, package-management/import preview and existing consent control; packages are not installed by the test harness and no permission grants are seeded.

Original inputs, unchanged:
- DemoMiniApps/hanlin-script-parity.hanlinNativeScript — SHA256 2c31e104d2b8e7a8c7356e3d2a15c2537e79266a1df1a8de7846deeddc923cc3.
- AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo — SHA256 f0b314cfb4d150b0451241e5d21a40d2ae4fcdbb10b2ae52976092dca05820ae.
Both original ZIP CRC checks pass.

MiniAppsProductionRuntimeUITests reuses the original NativeScript parity and Expo native-control assertion bodies with companion-specific navigation. NativeScript requires unpredictable nonce-bound JSC, Node and CPython execution, genuine HTTPS 200, original inter-app response, private storage and process relaunch. The network assertion is tightened to require actual VERIFIED 200 plus the nonce. Expo requires original native SwiftUI content, React toolbar state change, native settings sheet and toggle result, close and relaunch. Original rendering/runtime/Host implementation remains unchanged.

The new scope selects exactly these two methods. Original baseline scope still selects its original four MiniApps UI and three provider UI controls with the original 20 native storage checks. The new runtime-only scope explicitly marks those prior storage checks NOT_SELECTED; it does not call them fresh passes. Both scopes require zero skipped/failed cases and the canonical verifier confirms the requested method identities from the real xcresult.

The same workflow now uploads original logs/results before saving compiler caches. The current paired failures showed that caching otherwise delayed access to failure artifacts for several minutes. Cache data remains an optimization and is never test evidence.

Current validation: Swift syntax parse, Python compile and YAML parse passed. No native pass is claimed before execution. Actual two-product App Group routing, signed physical device testing and live model-provider acceptance remain separate.

The latest gate sequence is recorded in the continuation acceptance register. The signed standalone run 44263872088 built but failed independent startup before either UI case; paired run 44259936836 built both products and resolved their original primary shared container but MiniApps exited before tests. The original Frameworks runpath repair is under native validation in 44270714044. These are not successful engine/UI results. Native packaging now also requires the compiled original AppIcon and Assets.car; no artwork or original product identity is replaced.
