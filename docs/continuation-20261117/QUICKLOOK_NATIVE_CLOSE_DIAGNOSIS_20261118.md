# Original Quick Look close control — 2026-11-18

Run 44241109845 at 6815e67c32dcff7df299e57ccc6d014e833c0f77 compiled and rendered the actual image through the original SwiftUI Quick Look presentation. It failed at the English-label query for Done/Close; the OS exposes lowercase close and QLOverlayDoneButtonAccessibilityIdentifier in both captured accessibility trees. The screenshot visibly contains the native close button.

Only the UITest selector is corrected, scoped to the actual QLPreviewControllerView. The test still requires the actual remote image renderer and nonzero image bounds, a hittable native close button, real dismissal, all three HTTPS image sources, the original disabled history form and zero outbound actions. An explicit wait for the original preview to disappear strengthens the dismissal check. No product media implementation or expectation is removed.

Evidence:
- Job 134588997739 log SHA256 c6f27d7e8470e78a5f7a9083a2eba1b3c1a22b1e405d5881ab467b0309ea3dd0.
- Artifact 14400876327 API ZIP digest bd7d5f21df02c8d55348df531d64b68b571166a1cd4b843ef5ffbc27f5a707f3. Selected entries fetched with ZIP CRC verification; full ZIP digest not recomputed.
- Screenshot 1E8D59A3-60F4-4967-868F-4E2C329298A8.png SHA256 5dd6633ebcf63cee36c28cbf616b5c2355f625f0af98759b2052da750d001841.
- tests.json SHA256 588894dd965f0b4f7ab6a4cd1e78ce8d92c9267307cc4a4e83a75f5c14ec756b.
- Native AX attachments: 20AA244D-6B7C-4B1B-8A69-9162037C90A4.txt and 90A98D09-586A-4F2B-8839-08FC5C821E32.txt.

Acceptance remains PENDING until the single failed method passes on Apple native UI. The five other lifecycle/link methods from run 44234308320 remain separate evidence and are not needlessly rerun.
