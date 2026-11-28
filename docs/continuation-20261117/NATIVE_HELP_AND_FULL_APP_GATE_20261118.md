# Native help and full-app acceptance checkpoint — 2026-11-18

## Existing Hanlin help destinations
The original Chat guide and Profile guide/cost controls now open native offline help. The content describes the actual Chat/Library/Profile, original message text actions, Skill Center, separate MiniApps, storage and provider-dependent costs. English, Hebrew and Simplified Chinese are included. The old upstream QQ documentation, email recipient and WeChat marketing have been removed from these destinations. Support displays only build/OS facts and offers explicit copy/share and the verified public project source. The repository has no enabled issue tracker; no support email or issue URL is invented. Original legal/credit notices remain in Version Information.

New native selector: AI_HLYUITests/HanlinHelpUITests/testOfflineGuideCostsAndSupportReturnToTheOriginalProfile.
Windows Swift parsing passed for five changed Swift files; this does not prove Apple compilation or native UI acceptance. No message was sent by this change.

## Full app 44234045740
Source: 8cf1919724f082081c60ea5f7c1012bd286026d3.
The full arm64 simulator build-for-testing succeeded in Xcode 27/Swift 6.4.2. This verifies the original URLSession completion-handler delegate fix in the app's C++ interoperability configuration.
The run failed before boot/test execution because the dispatched selector list combined iPad suites with the two narrow iPhone Composer methods. The existing family guard rejected that request. This is a dispatch-scope error, not a successful test run or a simulator infrastructure failure.
Full job log SHA-256: 40afb00c27f347dba5138db5cfbefc4845b5708d65dd4145d3cd2d8261c37800 (16,832,142 bytes).
Build: PASS. Requested unit/UI acceptance: NOT_RUN. Motion B/C: NOT_RUN.
The corrected requests separate wide/native Phase 2 plus the new Canvas/text/help selectors from the two compact Composer methods. Both device families retain their original assertions and actual runtime selection.
