# Original Motion D native input observations — 2026-11-23

Status: **DIAGNOSTIC_CAPTURED**. Native D method passed; A/B/C acceptance was NOT_RUN in this scoped job.

- Run: https://github.com/davidpovarsky/hanlin-ai/actions/runs/45217195070
- Source: 5d0ea90d98b405d38b66bb735198b945225877ba
- Native job: 137841460104; actual iPad Pro 13 M5 simulator, arm64, iOS 27.2 (24B8117).
- Original XCTest method duration: 84.160907 seconds.
- Outer artifact: 14840585994, 57,298,126 bytes; SHA256 5d550fbb8ba97a7972f7f4feeba8db655bccb175cfd01a2aa6da2e93e0f8efe9.
- Digest and size match GitHub API, ZIP CRC passes, 83 members. Raw xcresult is readable and archived with SHA256 149db602844e4260d319b26eae6328d9c72e6ef39975054ee99e12db96c1a516.
- Unmodified native attachment names/bytes and their manifest are retained. receipt.json hashes all retained originals. Raw archive/video remain in the original GitHub artifact and Oracle working evidence.

The diagnostic records one native snapshot after each gesture. It does not treat the snapshot as a five-second delivery deadline and does not assert that every gesture delivered three actions. The passing test confirms that the required diagnostic observations were captured; it does not convert B's previous failed reversal assertion into a pass.

## Exact observations

| Phase | Control | Delivery | Callbacks | Callback gaps (ms) | Pre-action visible heights (px) | Later callbacks at intermediate geometry |
| --- | --- | --- | ---: | --- | --- | --- |
| native-default | rapid-native-outside | multi-tap | 3 | 50.0, 66.7 | n/a | [False, False] |
| native-default | rapid-native-scroll | multi-tap | 2 | 116.8 | n/a | [False] |
| native-default | rapid-native-plain | multi-tap | 2 | 117.5 | n/a | [False] |
| native-default | rapid-production-static | multi-tap | 2 | 115.8 | 0.000, 70.500 | [False] |
| native-default | rapid-production-animated | multi-tap | 2 | 116.9 | 0.000, 3.761 | [True] |
| native-default | rapid-production-animated | independent-coordinate-taps | 3 | 783.7, 1132.8 | 0.000, 70.500, 0.000 | [False, False] |
| immediate-touch-down | rapid-native-outside | multi-tap | 3 | 49.9, 66.8 | n/a | [False, False] |
| immediate-touch-down | rapid-native-scroll | multi-tap | 3 | 33.1, 83.8 | n/a | [False, False] |
| immediate-touch-down | rapid-native-plain | multi-tap | 3 | 65.9, 50.3 | n/a | [False, False] |
| immediate-touch-down | rapid-production-static | multi-tap | 3 | 50.1, 67.0 | 0.000, 70.500, 0.000 | [False, False] |
| immediate-touch-down | rapid-production-animated | multi-tap | 3 | 48.5, 67.2 | 0.000, 0.000, 1.968 | [False, True] |
| immediate-touch-down | rapid-production-animated | independent-coordinate-taps | 3 | 817.6, 799.3 | 0.000, 70.500, 0.000 | [False, False] |

## Result and next gate

The native controls and original production controls exhibit the same lost-callback behavior with default scroll touch delay; turning off that delay preserves scrolling and touch cancellation and delivers all three callbacks in this observation. The original animated production control genuinely reaches intermediate geometry during both relevant phases. Independent coordinate taps take long enough to settle and cannot validate rapid reversal.

This provides no basis for a speculative change to the original animation. The next gate is the unchanged original B acceptance method through the separately implemented B-only route. C's prior native and visual PASS from run 45166004801 remains reusable because its relevant inputs are unchanged. Full original chat composition, thinking/tool/source presentation, and physical-device acceptance retain their separate status.
