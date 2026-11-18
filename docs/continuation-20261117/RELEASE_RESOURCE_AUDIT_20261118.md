# Existing Apple release resources

The owner authorized completion of phases 2 and 3. The new opt-in audit in the existing
validate-app-split workflow reads the repository's already configured Apple resources.
It does not sign, install, upload, distribute, change an Apple account, or send a notification.

The script checks the distribution certificate/private-key correspondence, current dates and
team; each of the two apps and four existing extension profiles is checked against its
actual checked-in entitlements, exact bundle, team, certificate and distribution mode.
App Store Connect queries are GET-only and limited to the two existing product bundle IDs.
Only public certificate hashes, expiry/check results, role/bundle names and sanitized
registration/build facts are retained. Keys, decoded profiles, raw Apple responses and device
identifiers are excluded. Temporary profile files are destroyed after reading.

A missing secret means unavailable in that execution context. An empty Apple response means
not visible to the configured API key, not proof of global absence. Simulator/device inventory
is read-only and does not constitute a physical-device test. Metadata is not OS trust-chain
or revocation validation and does not prove an archive can be signed.

The existing release JWT dependency pin is reused. Six synthetic profile-policy tests pass
locally, covering expiry, team/bundle/signer mismatch, missing groups/capabilities,
development/ad-hoc/enterprise profiles and wildcard-vs-boolean entitlement handling.
These tests are not live signing evidence. Live audit results are pending.

Both phases and release acceptance remain open. The current project deploys all product
targets to iOS 27.0; no iOS 26 compatibility claim is made by this audit.
