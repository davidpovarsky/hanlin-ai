# Protected provider credential writes

The reviewed phase2 proposal builds on published37a246f4 readers and now activates verified Keychain writes in the original host settings. Real secret changes and new custom providers store only versioned references in the original SwiftData key field. Metadata-only saves retain the original representation exactly, including nil and empty values. Explicit per-row migration preserves a recovery predecessor. No opening, reading or unchanged save silently migrates a legacy row.

All three base sources match the frozen phase1 input. The original32,328-byte proposal SHA85e1adb2d9c2c5c543dfef1d1f46167979c97cc1adab377e3d3435f1d7d15458 is retained externally. Root applied one reviewed UI correction documented in root-review.json: explicit migration remains a migration even after a previous compact-publication failure; ordinary retry is publication only.

The full lane retains all phase1 tests and the original authority control, adding13 cases for a total19 selectors/28 planned cases. Three Windows Swift6.3.3 syntax parses and exact diff/source checks passed. Native Security/SwiftData results remain pending, and no physical extension/cross-device/account isolation or historical erasure acceptance is inferred.

Untouched legacy rows remain compatible. Original pre-phase1 clients cannot consume a secured reference, as authenticated in the source audit. Updated clients resolve using the original host Keychain policy; iCloud row and item arrival may be asynchronous. The settings text states that updated Hanlin and iCloud Keychain are required on other devices. This is an operational compatibility boundary, not an assertion that remote synchronization has occurred.
