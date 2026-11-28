# Original Motion D — simulator readiness failed before testing

[Run 45181755996](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45181755996), attempt 1, used exact source **5d0ea90d98b405d38b66bb735198b945225877ba**. One dispatch selected only `ChatMotionProofUITests/MotionUITests/testDRapidInputDiagnosticOnly`, with all six original variants in both scroll phases, including independent coordinate taps. A, B and C were not selected.

## Actual result

The GitHub-hosted runner **1000024686** was allocated. Its native job ran from **13:23:33 to 13:30:14 UTC** using Xcode 27.2 (27B52), Swift 6.4.2 and the selected iOS Simulator 27.2 (24B8117) runtime. The new owned iPad Pro 13-inch (M5) simulator accepted `simctl boot` in 5.227 seconds. The original 180-second `bootstatus` deadline then expired at 181.168 seconds; the single original 20-second recovery shutdown also timed out at 22.491 seconds. Preflight failed with **Owned Motion recovery shutdown failed**. The final owned-device cleanup also timed out and remains in the original log.

**Fixture preparation, compilation, XCTest and all 12 diagnostic cases are NOT_RUN.** No action receipt, aggregate report, screenshot, video or result bundle was created. The failure is simulator readiness, and provides no new evidence about the production animation or input delivery. Original input, assertions and deadlines were unchanged.

## Provenance and completion

Artifact **14821829613** contains 19 original files, with API-verified size **13,368 bytes**, SHA256 **11dc996521fd17b43e0df9761d1ad1b3d61e1d70de3c12654058aa1124284ea1**, and valid ZIP CRCs. Its original readiness receipt, logs and performance record are retained here. The large runtime/device inventories remain in the verified original archive on Oracle and GitHub; their exact hashes are in `original-artifact-inventory.json`. The environment summary is derived from that artifact and is explicitly preflight selection evidence.

The sole finite watcher ended at **13:30:32 UTC**. Its two process IDs are absent and the owner lock is free. No retry, new probe or product change was submitted. The earlier C test and full-screen visual acceptance remain valid; B's original observation remains unresolved, D still lacks executed observations, and A has not run on current source. The paired MiniApps cases remain separately held for actual full-app compilation qualification.
