# Canonical Motion native result — 45133334293

**B failed; C passed its XCTest assertions. Overall Motion acceptance remains open.** This is an executed result on the canonical HanlinChatUI profile, not a build-only result. No original animation, gesture, threshold or assertion was changed during diagnosis.

The [native run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133334293) used exact source `6772dce6304fc6761a2200314f7d2020dc782e47`, Xcode27.2 / Swift6.4.2 and an arm64 iPad Pro13-inch(M5) simulator running iOS27.2. Native compilation took270s. All363 selected canonical source/resource inputs, eight actual dependency trees and six resource-bundle instances were recorded before execution. The reviewed original Equatable1.4.1 revision was admitted before compilation and verified afterward with automatic resolution disabled. [The receipt](receipt.json) records the exact hashes; the full resolved closure is in [sdk-resolved-inputs.json](sdk-resolved-inputs.json).

## B: delivered input, unproven intermediate reversal

The unchanged test failed at line160 after40.123s. Both warm-up actions and all three burst actions were delivered. Burst gaps were56.9ms and59.2ms. The final state was expanded, but the cached pre-action outer-layout heights were0,0,0. The case stops here, so its later preset switching, nested state, drag cancellation, persistence and Reduce Motion checks did not execute. The [original test log](test.log) and [xcresult test export](tests.json) preserve the exact result.

The video shows relaxed motion with `shimmer=true;numeric=true`. Original warm opening and closing both visibly traverse intermediate positions. A second analysis decoded the burst's native variable-rate frames without resampling and compared the unchanged footer glyphs against the collapsed reference. The counter crop was read visually in the same frames:

| Video PTS | Visible action counter | Footer top, physical pixels | Observation |
| --- | --- | --- | --- |
|16.340000|3|627|First burst action is visible; footer still collapsed.|
|16.361667–16.390000|4|627|Second burst action is visible; footer still collapsed.|
|16.418333|5|628|Third burst action is visible; first one-pixel movement.|
|16.838333|5|839|Final fully open footer position.|

The [native counter frames](visual/burst-native-counter-16p1.png) and [same-frame footer trace](visual/burst-native-footer-trace.json) are derived from the original video. They are evidence analysis, not another UI execution. The unchanged footer template matched with3–14 differing thresholded pixels among25,000 reference pixels; the full trace, thresholds and extraction commands are retained.

This evidence is consistent with the failed cached-height assertion: the recorded burst does not show an intermediate reversal before the third action. It does **not** identify a product scheduling defect. Video PTS is not application uptime, recording can omit frames, and no private render-state inspection was used. Source review found no wrong index slicing, explicit delay or unguarded stale collapse completion. Changing animation timing or weakening assertions is not justified by this receipt. The existing original D case is the smallest independent input-delivery comparison if further diagnosis is scheduled; D never accepts B.

## C: automated pass and visual limits

C passed33.586s of original long content, RTL, accessibility text size, orientation, completion and collapse assertions. The original [expanded portrait screenshot](visual/faa4ee413e06f3c844b6.png) visibly contains the Hebrew/Arabic/English text with the original thinking header. The [finished collapsed portrait](visual/028ef51d26d10d663300.png) shows the footer and stopped shimmer. Fixture text deliberately includes literal Markdown; this does not accept the production Markdown renderer.

The [original landscape screenshot](visual/6aa76d91593c0923c377.png) has PNG dimensions2752×2064 and EXIF Orientation8. Its oriented image includes a black region and clipped content. The original capture uses `app.screenshot()`. Its cause is not established, and the automated C pass is **not** a clean landscape visual pass. The unchanged original PNG bytes and extraction mapping are retained. A full-screen capture comparison would distinguish the capture boundary from the actual app scene if that visual scope is rechecked.

## Raw evidence and pending scope

The verified native artifact is `chat-motion-ui-45133334293`, ID14802375245,83,126,367bytes, SHA256`26ef10cd19762ac227cca61964abbce4e2c7af24f55372d4c42060faffb909b4`. It includes the finalized readable xcresult archive (SHA256`c0c0f2c57b7340fa4323a0f89469fdddb27ca02eb8a12a105c1254b9510612b7`) and original27,197,640-byte video. The large artifact/video remain in the original GitHub artifact and Oracle evidence directory; they are not duplicated into Git.

A and D were not dispatched. B's later assertions remain NOT_RUN. The current paired MiniApps and full-app gates are separate scopes and are not accepted by this fixture. No physical-device result is claimed.
