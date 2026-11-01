# TestFlight delivery — 0.7.3 (87401)

[נועם | DEV] [MAIN_SESSION] Delivered at the owner's explicit 2026-11-01 request. Owner iPad acceptance remains pending.

| Field | Observed result |
|---|---|
| App | ChavrusaChat, com.itorah.chavrusachat |
| Version / build | 0.7.3 / 87401 |
| Source | 279f0ead777b961728ed91386c136e7e33659c36 |
| Branch | integration/hanlin-dual-widget-engines-20261029 |
| Workflow | [41310977352 — SUCCESS](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41310977352), signed job 38m00s |
| Toolchain | Stable Xcode 27.1 (27A9275), iOS 27.1 SDK, per-job DEVELOPER_DIR |
| Archive / export | EXECUTED_PASS, signed Release App Store Connect IPA |
| Signature / provisioning verification | EXECUTED_PASS for app and all four extensions, matching existing team and App Groups; existing distribution identity/profiles reused |
| App Store Connect validation | EXECUTED_PASS, no validation errors |
| Upload | EXECUTED_PASS, UPLOAD SUCCEEDED with no errors at 2026-11-01T13:49:55Z |
| Apple processing | VALID, observed 2026-11-01T14:00:38.9875840Z |
| Temporary signing cleanup | EXECUTED_PASS |
| IPA SHA256 | cf18f0edad4b5ddd49b089f77e024fc5234ca11757dcf75827e637fc91d2ef27 |
| Retained artifact | ChavrusaChat-signed-ipa-87401, ID 13086780134, 259819005 bytes |
| Artifact ZIP SHA256 | e9eabda71bd0a69ffa21b4b106f7001170b778c7b6cb4f6fb3ef14f2d91b9ea3 |

Distributed extension identifiers: com.itorah.chavrusachat.share, com.itorah.chavrusachat.widgets, com.itorah.chavrusachat.translation-provider, com.itorah.chavrusachat.notification-service. The archive verification checked their signatures, provisioning/App Groups and build number 87401. Fifteen required main-app privacy purpose strings were present. Signing secrets were neither replaced nor committed.

No additional optional XCTest/device workflows were run for this delivery. The signed workflow retained its existing preparation, packaging, signature and Apple upload checks. Earlier optional UI retry 41308904140 and unsigned-device retry 41309874110 were cancelled at owner request. This upload is distinct from public App Store release or a main merge; neither was performed. Asana remains read-only.

The imported owner changes through b5ce6f60d827436a4d39219dc08e9c4144012ed0 are included. Widget corrections add no further changes to the four frozen Chat files relative to that owner head. Actual SpringBoard widget button/toggle behavior and physical iPad acceptance remain OWNER_DEVICE_QA_PENDING: see [device checklist](DEVICE_ACCEPTANCE_CHECKLIST.md) and [CI evidence](CI_AND_DEVICE_RESULTS.md). VALID processing is delivery evidence, not device interaction acceptance. The latest independently audited native appex dependency closure is the simulator result in 41304461973; this signed workflow verifies device signatures/packaging rather than claiming a new dependency-closure audit.

Raw workflow log, run/step metadata and artifact metadata are preserved outside Git at C:/Users/DAVID/.codex/backups/hanlin-testflight-41310977352. The IPA and dSYMs remain in the linked workflow artifact.
