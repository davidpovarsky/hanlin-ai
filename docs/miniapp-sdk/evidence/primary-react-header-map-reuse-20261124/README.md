# Original ReactNative header-map reuse correction

The original preparation projected the upstream module map and then deliberately removed maps from active Headers paths. A later preparation reused that stripped XCFramework, cleared ModularFrameworks, warned about the absent source map, and returned successfully. The actual primary MiniApps build then failed to resolve React_RCTAppDelegate.

The correction preserves the original map bytes in non-discoverable JSON metadata bound to the original artifact SHA, exact iOS slices, HeadersPath and content digest. Fresh raw maps take precedence. Missing or invalid reusable source causes only ReactNativeHeaders to be re-extracted from its locked artifact. The original source is validated before replacing the consumer projection. Intentional duplicate-module cleanup, original headers, imports and explicit-module settings remain unchanged.

The retained focused proof ran on Oracle Linux with Node 24.22.0, using the exact production nested staging function and complete checksum-verified original ReactNativeHeaders 0.88.1 archive. The baseline failed on its second pass. The corrected stage passed twice with the same 2,808 projected file hashes, the original AppDelegate module and all nine original headers. Five damaged/missing source variants were rejected before clearing output; fresh raw input restored malformed metadata. This was one meaningful regression case, not an Apple compiler/app test.

The production-source review also checked the existing bundle cleanup, slice pruning and CI cleanup: the JSON record survives them and is not a Clang module-map filename. No duplicate compilation or proof rerun was performed after the continuation refresh; the existing completed red/green outputs were recovered.

Attempt5's native preparation, export and inputs passed. MiniApps build-for-testing failed with exit65 after202.4seconds at20:09:11UTC. AI build and all52 application cases did not run. The raw terminal state and logs are retained losslessly, including the compiler log SHA97914eff511dd01491868bfa0232ccae43d6a81632d45cf9ae0897b84e7de3e3. Earlier stale RUNNING snapshot wording is superseded by this terminal result.

The corrected full Apple preparation/build/52-case route remains pending. The normal final Host provenance hook remains required; this wrapper is a direct native-artifact input, so the prepared catalog must be refreshed. It is outside direct SDK/source-inventory/reachability inputs; no separate four-audit rerun is needed solely for this wrapper.
