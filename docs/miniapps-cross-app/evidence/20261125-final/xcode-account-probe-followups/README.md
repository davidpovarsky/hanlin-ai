# Actual Xcode and Apple profile follow-ups — 2026-11-25

These are actual Apple resource probes, never original application acceptance or TestFlight delivery.

- attempt2-distribution built and archived the dependency-free unsigned profile discovery product, then attempted App Store export using the existing distribution identity. Export failed with cloud signing permission and missing profile errors. The original keychain identity remained unchanged. Receipt SHA256 9f40ff95f3addd81b4c2a3a499ffa2344f2e9486b1fc17af43680e617a4d63dc; sanitized actual log ae0e92f612fc0075cb2af0ac876d5f21d1ff3e83cf4f97f4aa788252d6213741.
- manual-profile-readback stopped before any mutation because the first probe incorrectly restricted the existing bundle to IOS. Apple actually reports the same exact resource, identifier and team as UNIVERSAL; the existing audited inventory already accepts both.
- manual-profile-readback-universal also stopped before any mutation because the probe's copied certificate fingerprint had one mistyped nibble. Independent fresh reads of the existing local public DER and Apple record B8HSX5CPJ4 matched SHA256 5aefaf80b344410af7da85678fcb19de9a4be6885a846644df974b1ee38eba4b, SHA1 644940fcf25d1730dbd1bf7596aeba7229e2b8fd. The corrected probe additionally checks the actual local keychain certificate bytes.
- One invocation with an incorrect entitlement filename failed locally before creating its attempt directory or making Apple calls; SentinelX job job_c66cea5c8cb3. The corrected invocation used the exact original HanlinMiniAppsShare.entitlements.
- manual-profile-readback-exact-certificate created exactly one missing IOS_APP_STORE profile, resource 9T4ZL4595L, using that same existing distribution certificate. Actual Apple CMS readback passed team, bundle, expiry, distribution and certificate checks, but returned **no App Groups**. Required original groups group.com.itorah.chavrusachat and group.com.itorah.shared are missing. This resource is blocked for release, not installed or used as a qualified application profile. CMS SHA256 89cc50aee0d73d1fccb8493fb9b15c9f89a0705e99b6194ca01d1f3c7fdce16e; actual receipt 24c69f1b7a0a32e7c8232bd332b99e3c3add962a5d6d0ad7b3a37a7a6105d973.

Original failed receipts remain unmodified. No certificate was revoked, recreated or exported; no private key or JWT is in this packet. Missing profile grants must be reconciled before another issuance; the helper refuses repeated issuance against unchanged incompatible profiles.

## Existing distribution identity through automatic archive

A third actual Xcode route used the established normal-m1 env/unlock helpers, explicit original distribution identity and keychain, plus an explicit original App Groups SystemCapabilities target declaration. It stopped in GatherProvisioningInputs with conflicting settings: automatic archive signing requires Apple Development, while the exact existing Apple Distribution identity was manually selected. Actual exit65 at06:48:36UTC. No certificate change or application archive was produced. Log SHA256 bd9330b4d61f2d9ecd36150303a8094cf5ff51571d0ef8c9db3c0a2ee8a9ab7e.

Together the three distinct real Xcode routes and actual direct-profile CMS readback establish this account boundary: automatic development cannot issue another certificate under the current limit, automatic distribution export lacks cloud-signing permission, forcing a distribution identity conflicts with automatic archive signing, and the original certificate can issue a manual App Store profile but its actual App Group grants remain empty. No signing requirement is removed to work around this.

Apple's supported App Group assignment is through the Developer account Configure/Assign flow or Xcode's capability group checkboxes. The current documented public CapabilitySetting keys do not expose group assignment. Sources checked on2026-11-25:
https://developer.apple.com/help/account/identifiers/enable-app-capabilities/
https://developer.apple.com/documentation/xcode/configuring-app-groups
https://developer.apple.com/documentation/appstoreconnectapi/capabilitysetting
Anytype also has no accessible ASC app record on the exact bundle lookup; Apple's documented apps API manages existing app records and directs creation to the website:
https://developer.apple.com/documentation/appstoreconnectapi/apps

The prior interactive Apple login was cancelled. It has not been retried. Source integration and actual native acceptance continue independently; distribution remains blocked until actual account resources carry the original required grants.

## Original Anytype ASC association readback, 07:06 UTC

The exact original Anytype bundle lookup returned HTTP200 with an empty complete apps list. The positive-control lookup for com.itorah.hanlinminiapps in the same authorized session returned the existing app6836449016. The two documented bundle-to-app relationship routes returned HTTP404 PATH_ERROR_REALTIONSHIP (URL path not valid); those route errors establish neither permission denial nor global absence of an app record. The supported conclusion remains **no accessible Anytype ASC record on the exact bundle lookup**, requiring account-level verification before creating anything.

The immutable readback SHA256 is058f194cd4c0cbd494420a6b2b26952d8c15cd0fd09c677b31e081ff9df33df6. Its records are in actual request order:
1. GET /v1/bundleIds/KTRM7V4TCD/relationships/app; no query.
2. GET /v1/bundleIds/KTRM7V4TCD/app; fields[apps]=name,bundleId.
3. GET /v1/apps; filter[bundleId]=io.anytype.app.NA6HPWARQ2; fields[apps]=name,bundleId; limit=200.
4. GET /v1/apps; filter[bundleId]=com.itorah.hanlinminiapps; fields[apps]=name,bundleId; limit=200.

This request metadata records the executed audit input; the original response receipt remains unchanged. No app record or identifier was created by this read-only audit.
