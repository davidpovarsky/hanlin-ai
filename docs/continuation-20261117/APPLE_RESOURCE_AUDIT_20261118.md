# Apple resource audit — 2026-11-18

Read-only run: https://github.com/davidpovarsky/hanlin-ai/actions/runs/44234890729
Source: 39c3a5e825bbcfef2662c6b745b99034907f7720.
The existing Apple Distribution identity matches its private key and team, valid through 2027-09-07. Four extension profiles cover their actual original entitlements. The current AI profile lacks com.apple.developer.kernel.extended-virtual-addressing. The MiniApps profile secret and visible App Store record were absent. No physical device was visible on the runner; physical tests did not run. iOS 27.0/27.1/27.2 simulator runtimes were observed.

Sanitized report SHA-256: 1e6c0bdf071bfa97e746310d18d5d1b1a1d9d09ef706a33d058340dcf3d16419.
Artifact: 14398515439; GitHub artifact digest cb14643d594f212eb50b36a378c6ac5af26fa112d68c78e56857b0281d22b9ca.

## Corrected identity lookup
The first audit counted a limited Apple identifier-filter response, which may include extension prefix matches. Its count of two AI bundle candidates does not prove duplicate product IDs. The updated audit requires the exact identifier and IOS/UNIVERSAL platform, records pagination completeness, reads the enabled capability names and checks up to eight active portal profiles against the actual source entitlements and existing public certificate. Profile contents and resource IDs remain in process memory/owner-only temporary files and never enter artifacts.

## Provisioning path under investigation
Apple's public CapabilityType documentation does not list Extended Virtual Addressing, and enabling APP_GROUPS alone does not establish assignment of the original groups. Do not remove required source entitlements or invent a public API for those operations. Apple's documented Xcode automatic signing with App Store Connect authentication is an available next path under the owner's authorization. A metadata audit is not a signed archive or release acceptance.
Official references:
https://developer.apple.com/documentation/appstoreconnectapi/capabilitytype
https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-13-release-notes
https://developer.apple.com/videos/play/wwdc2021/10204/

The current repository policy explicitly requires current stable iOS/iPadOS 27 and rejects backward compatibility. No iOS 26 product acceptance is claimed. Release remains NO_GO.
