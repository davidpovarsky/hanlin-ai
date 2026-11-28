# TestFlight 0.7.3 (93401) — 2026-11-10

[תומר | INT] [MAIN_SESSION] Owner explicitly authorized a new TestFlight containing all implemented corrections, including Runtime, via CLI/API only. Delivery is **VERIFIED / IN_BETA_TESTING**; physical iPad acceptance remains open.

## Delivery evidence

- Repository/branch: `davidpovarsky/hanlin-ai`, `fix/hanlin-approved-plan-20261108`, based on Pass 7.
- Uploaded source: `7fa8fe26257c20f57846702fd13db515a0441bfc`.
- [Signed workflow 42728397166](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42728397166), job `129539877419`: SUCCESS, 56m17s.
- Stable Xcode/iOS SDK: 27.2; fresh signed Release archive and App Store Connect export.
- Version/build: `0.7.3 (93401)`.
- App Store Connect app ID: `6811910017`; build ID: `75dd3258-c7a6-44a0-8dcb-11afced4931a`.
- Apple processing: `VALID`; internal state: `IN_BETA_TESTING`.
- Reused the one existing internal group from build `91801`; no new testers/groups. External state is `READY_FOR_BETA_SUBMISSION`; no external/public release was submitted.
- CI-computed exported IPA SHA-256: `96fe9c8a3e15070ded1a1c2b6c966495ff3af43b2fd1f38456487ff36153316b`.
- [Signed IPA, dSYMs and verification logs](https://github.com/davidpovarsky/hanlin-ai/actions/runs/42728397166/artifacts/13726597810), retention 30 days. The IPA hash is the CI result; the full IPA was not downloaded and rehashed locally.
- Temporary signing material cleanup: EXECUTED_PASS.

## Signing inventory

Existing Apple team/certificate/profile identity was retained. CI matched every signed bundle and embedded profile against the existing `APPLE_TEAM_ID`; actual public identity evidence is in the signed-entitlement/profile artifacts. No credentials or identities were replaced.

| Role | Bundle ID | Result |
| --- | --- | --- |
| Main | `com.itorah.chavrusachat` | EXECUTED_PASS |
| Share | `com.itorah.chavrusachat.share` | EXECUTED_PASS |
| Widgets | `com.itorah.chavrusachat.widgets` | EXECUTED_PASS |
| Translation | `com.itorah.chavrusachat.translation-provider` | EXECUTED_PASS |
| Notification service | `com.itorah.chavrusachat.notification-service` | EXECUTED_PASS |

App Groups: `group.com.itorah.chavrusachat` and `group.com.itorah.shared`. iCloud: `iCloud.com.itorah.chavrusachat`, CloudDocuments/CloudKit. Existing production APNs, Siri, translation and WeatherKit entitlements passed. Deep/strict signatures, expected architectures, extension locations/build numbers and 15 nonempty privacy-purpose strings passed.

## Runtime inclusion in the shipped IPA

- Exact verified private Runtime candidate: run `42687189577`.
- Locked Runtime ZIP SHA-256: `aa788654a883d8e1bca3f177697e8505168dd6cbabcf712dbfae058bd1e46d8d`.
- Exported Node image UUID matches the prepared Device framework; signing changes binary bytes, so an entire signed Mach-O hash is not used for this comparison.
- Packaged Runtime manifest equals the verified prepared manifest.
- Packaged Host ZIP SHA-256 equals the freshly prepared production Host ZIP.
- All three packaged-input guards: EXECUTED_PASS before Apple validation/upload.
- No Node rebuild or separate Runtime release was needed for this delivery. The same verified native archive was consumed directly.

Application source, fixtures, test assertions and runtime lock/binaries are unchanged from SDK-verified `5c656fdb`; later changes connect signed distribution and add packaging/audience checks. Prior Debug/Simulator evidence retains its original scope: app `42715548913` passed eight methods/two suites (including three canonical Skill language cases) and four UI methods; native `42687189577` built both slices and passed 128 tracked descriptor cycles with zero warnings. Those tests are not claimed as freshly executed Release/device tests. Release archive, signatures, packaged-input checks and Apple readiness executed freshly here.

## Owner iPad acceptance

Update the existing app through TestFlight to **93401**. Test source-button zoom and All Models/back, Hebrew/English microphone recording/stop/file output, existing Widget instance selection/actions without clearing data, Skills/TypeScript execution, and Node HTTPS including background/resume. Physical hardware, long suspension and original device symptoms remain OPEN until actual owner evidence. App Store/main merge were not performed.

Local evidence: `build/testflight-runtime-42728397166.log`, final run metadata, `build/testflight-runtime-93401-readiness.json` and `build/testflight-runtime-93401-delivery-verification.json`. App Store API state and existing internal audience were checked by the actual uploaded-build verifier.
