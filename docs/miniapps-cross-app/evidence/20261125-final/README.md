# MiniApps final integration — 25 November 2026

## Current source

The final integration branch is `codex/hanlin-miniapps-final-integration-20261125`.
The native gate is executing from source9ef80a6ddfc997724360a9a34bb1d05cbf7cad40.
It includes PR18 source60afd124, PR19 current sourcec259b722, native per-window
package work8557d605, shared Picker7b8cbba3, and current consumer SDK4e921b951.
Nine source conflicts were individually reconciled. The original Mac canonical
generators materialized the notification extension and SDK source membership;
strict source/target graph verification then passed. Export now freezes its exact
build receipt, and can publish a build-only consumer artifact while native tests run.

The dependency conflict retains `swift-ai-sdk@3f38f1302764635c9991d0d00fd7b12471a5373c`.
GitHub comparison on 25 November confirmed that the former `07431abccbfb151ca2dab67bca6cf86fcb2bd3b8`
is its ancestor by two commits. The original navigation-transition Apple evidence is retained.

The picker now transports original asset/package icons as bounded PNG data and localized
subtitles, reads older schema-v1 catalogs, filters context-incompatible apps consistently,
uses the same native editing view in source-app settings, and prevents launching an app
while editing favorites. Hebrew bridge error strings are supplied. Two new catalog
persistence/backward-compatibility tests are added and passed on the primary Mac.

At 05:09 UTC the exact package from source4e37d47a5 (implementation7b8cbba34)
compiled both products, including native SwiftUI Picker, and executed13 actual tests:
13 PASS,0 FAIL,0 SKIP. This is a macOS Swift package run, not iOS app acceptance.
The command, toolchain, log and content hashes are in bridge-mac-4e37d47a/.
It used123 MB incremental storage and completed in12 seconds.

## Live signing inventory

`signing-profile-inventory.json` was collected from the installed App Store Connect key
on the primary Mac in the m1 SSH user session at 01:43 UTC. All six capability/profile
queries completed without errors. Its SHA256 is
`36317a7f2749fee1254f8dd0eccbd6e58eb699e715f0f2975883cbfaccbed4cf`.

This contains public resource identifiers, decoded granted entitlements and certificate
hashes, not private keys, tokens, device identifiers or raw provisioning profiles.

| Product | Observed distribution status |
|---|---|
| MiniApps, com.itorah.hanlinminiapps | One active profile includes group.com.itorah.shared; ASC app 6836449016 has historical build 8301 VALID |
| Otzaria, com.davidpovarsky.chavrusatext | 81 profiles inspected; no active profile grants the shared group; original two groups remain; ASC app 6809559414 has historical build 11201 VALID |
| Anytype, io.anytype.app.NA6HPWARQ2 | Main and Share/Notification extension profiles lack required groups; no main profile grants Multicast; exact ASC app lookup returned no accessible record |
| Anytype widget | Three profiles inspected, none with shared group; preserve its original source entitlement requirements |

The App Groups capability is enabled on the bundle identifiers, but that is distinct from
assigning the actual group to profiles. Nothing was removed or revoked. Installed Xcode
preferences contain an empty Apple ID account list. The connected browser is not signed
into the Apple Developer portal. Account assignment and Anytype app-record creation
remain open. Existing historical TestFlight builds are not results of this integration.

The installed distribution identity is usable in the normal m1 SSH bootstrap. SentinelX's
direct System bootstrap produced misleading keychain/cms failures; no trust or certificate
changes were made to compensate.

A fresh independent API read at05:14 UTC confirmed unchanged profile grants and
historical build numbers, with zero API errors. See signing-profile-inventory-0514.json
(SHA256 cb568176d6f52636c0b1dea8e4424fc7fb7d29401b6911bb65aa88e2a5a05d88).
The interactive Apple sign-in request was cancelled; it was not retried.

## Native evidence boundary

The original artifact 14892950855 from run45325776062 was authenticated and its original
xcresult inspected on the Mac. It contains12 actual tests:9 passed,3 failed. The two
window cases stop at installation because package metadata lacks required plugins.
The nonce case enters the actual runtime but does not reach its required output.

Historical intermediate result: a separately owned PR19 six-case diagnostic on1812bff5 reported3 raw passes and
3 raw failures by01:29 UTC. Its nonce failure persists; SDKOnlyNativeScript also reports
TNSLabel undefined because original TNSWidgets/NSCWinterTC metadata was excluded.
That correction is actively owned in the parallel SDK lane. Do not duplicate it or claim
the callback unit-test pass proves the full application. The full52-case SDK gate remains
pending. That snapshot was superseded during the sign-in wait. The parallel owner reports
real upstream metadata/cold-start fixes on newer PR19 sources; the native integration
lane is rechecking exact sources and evidence before accepting them here.

Native window work and original editor integration remain in separate owned worktrees.
No new full application acceptance, official final archive, upload or task completion
is asserted by this source/evidence checkpoint.

## Resource admission

The current mac-storage-lifecycle-v2 policy admits work by actual incremental phase
needs, concurrent growth and a situational OS margin. The200/100/50 GB levels are
aspirational/warnings, not hard stop thresholds. One writer per mutable cache remains
required. Cleanup of a bounded inactive compiler cache recovered1.07 GB while
retaining source, products, logs, native evidence and newer reusable configurations.

## Current controls and original native run

The merged Node SDK resolver and asynchronous original-bridge selection controls
ran on5cca5d79:18 PASS,0 FAIL,0 SKIP. Their source modules are unchanged in571a.
See merged-source-controls/. The first attempt failed before test execution because
sparse-checkout source files were absent; the original log is retained. Exact tracked
files were materialized and the actual test run then passed. These controls are not
native application acceptance.

The actual Mac23-case run started from571a in
/Users/m1/builds/hanlin-miniapps-final-native-20261125/build/native-final-evidence/attempt-571a1ab7-01.
A distinct private APFS cache reuses only content-verified original dependencies;
the donor application's acceptance is not reused. Source admission passed.
Actual build/UI outcomes will be recorded separately when available.

## MiniApps extension identities

The original source declares four MiniApps extensions. Their necessary identifiers
were absent from the earlier Apple inventory. They were registered with the same
existing team and parent namespace; public capability readback passed at05:38 UTC.
The exact source entitlements and target recipe are bound in extension-signing-plan.json.
The original failed CloudKit-version request and identifier-prefix lookup are retained
next to the corrected successful receipt; no uncertain mutation was blindly retried.

- Widgets: com.itorah.hanlinminiapps.widgets / R2N62AFGF6; App Groups, HealthKit, HomeKit, iCloud (XCODE_6).
- Share: com.itorah.hanlinminiapps.share / WM658PXWFD; App Groups.
- Translation: com.itorah.hanlinminiapps.translation-provider /99R3HH5NK9; App Groups.
- Notification: com.itorah.hanlinminiapps.notification-service /9YMYD4YPQ6; App Groups.

The API added its normal In-App Purchase capability by default; no original capabilities
were removed. Actual group/container association and matching distribution profiles
remain unverified for these extension IDs. Their public capability registration does
not establish an exportable signed MiniApps product. No certificate was created,
revoked or exported, no tester was contacted, and no new TestFlight build is claimed.


## 05:59–06:03 continuation

The current PR19 correction c259b722 matches the installed Xcode27 imported
notification delegate async result (Int) and forwards the original delegate's
presentation bits unchanged. It is merged in9ef80a6d. The native owner refreshed
original Host/SDK provenance:169 PASS,0 FAIL,1 existing opt-in SKIP; original SDK
examples and source graph passed. The actual MiniApps build is in progress.
No original23 application case is counted as passed yet.

The571a first attempt stopped before compilation on generated Artifacts inside
its isolated copied opentelemetry checkout. The complete generated tree was
preserved with hashes outside that checkout; tracked dependency bytes and the
donor stayed unchanged. The second571a attempt was stopped by its owner after
the current notification correction became available. Both failed/interrupted
attempts remain evidence, with no application acceptance credit.

The signed-product checks now require every original MiniApps extension, through
both PlugIns and ExtensionKit containers. The local profile resolver reuses the
same full entitlement validation for all five MiniApps roles without changing
the existing AI main/Widgets wrapper. The43 focused portable controls passed
at05:55:22 UTC; see local-miniapps-profiles-controls/. These fixture-based
controls do not establish actual Apple grants, signed products or native app
acceptance. Their sparse-checkout first failure is retained separately.

A fresh installed-key Apple read began at06:00 UTC and completed without errors.
The full sanitized audit is signing-post-registration-inventory.json,
SHA25664dbd3ea3f323e206a88edf9bdb43c59c8411bb1ee4c42577a0ef6e2a75db2e6.
All four newly registered MiniApps extension IDs and capabilities persist;
none has an issued profile. Existing Maktabah and Anytype grants remain
insufficient. Historical App Store Connect build numbers are unchanged; no new
TestFlight upload or processing is claimed.

## Native picker reference

The source review used Apple's current iPad sharing customization instructions:
https://support.apple.com/guide/ipad/customize-sharing-options-ipad29729577/ipados
and activity-view guidance:
https://developer.apple.com/design/human-interface-guidelines/activity-views

The shared native editor provides the matching More/Edit path, favorites,
visibility controls, native reordering and Done. Original icons and short
localized titles remain part of the shared catalog; applicable choices are
filtered by the incoming context. Unlike per-app system share-menu preferences,
the user explicitly requested a common preference store, which remains in the
shared App Group. This is a source/reference review. Screenshots from actual
consumer acceptance, Hebrew/RTL and phone visual checks are still pending.
