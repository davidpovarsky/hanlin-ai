# MiniApps final integration — 25 November 2026

## Current source

The final integration branch is `codex/hanlin-miniapps-final-integration-20261125`.
It includes PR18 source `60afd124`, PR19 execution source `1812bff5` via
`27b891d8`, shared picker correction `7b8cbba34`, and consumer SDK lineage
`f8cf6ca54` via merge `309bf4c61`.

The dependency conflict retains `swift-ai-sdk@3f38f1302764635c9991d0d00fd7b12471a5373c`.
GitHub comparison on 25 November confirmed that the former `07431abccbfb151ca2dab67bca6cf86fcb2bd3b8`
is its ancestor by two commits. The original navigation-transition Apple evidence is retained.

The picker now transports original asset/package icons as bounded PNG data and localized
subtitles, reads older schema-v1 catalogs, filters context-incompatible apps consistently,
uses the same native editing view in source-app settings, and prevents launching an app
while editing favorites. Hebrew bridge error strings are supplied. Two new catalog
persistence/backward-compatibility tests are added; their Apple execution is pending.

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

## Native evidence boundary

The original artifact 14892950855 from run45325776062 was authenticated and its original
xcresult inspected on the Mac. It contains12 actual tests:9 passed,3 failed. The two
window cases stop at installation because package metadata lacks required plugins.
The nonce case enters the actual runtime but does not reach its required output.

A later, separately owned PR19 six-case diagnostic on1812bff5 reported3 raw passes and
3 raw failures by01:29 UTC. Its nonce failure persists; SDKOnlyNativeScript also reports
TNSLabel undefined because original TNSWidgets/NSCWinterTC metadata was excluded.
That correction is actively owned in the parallel SDK lane. Do not duplicate it or claim
the callback unit-test pass proves the full application. The full52-case SDK gate remains
pending. Its latest published evidence-only PR head is05a40d39.

Native window work and original editor integration remain in separate owned worktrees.
No new full application acceptance, official final archive, upload or task completion
is asserted by this source/evidence checkpoint.
