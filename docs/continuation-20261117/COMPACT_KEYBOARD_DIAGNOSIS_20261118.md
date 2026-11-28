# Compact composer keyboard correction

Status: implemented; original native UI acceptance pending. Not a product PASS.

Evidence: app run 44222118230 at f962b54b; native inspection 44226095140 at 33168b5a.
Inspection artifact 14394553113 SHA-256 3b277fcd53470a509855ae522dfe2a8b0768653f82e7ef4954e030a0d33fa42e.
Normal text AX: window 420x912; launcher (33,734,52,52); editor height 0; keyboard top 609.
Accessibility XXXL AX: launcher (33,677.7,52,52); editor height 0; keyboard top 609.
Normal-text video frame SHA-256 b04549f0402a0f8724c29856d5006e99fbcddff042daa4b35f35aab2e903b0b8 shows the composer obscured by the keyboard.

The earlier intrinsic-size correction prevented the model hosting controller from expanding the whole workspace beyond the window. It did not fix keyboard placement.
The persistent compact composer now uses the native bottom safe-area inset. Its height budget comes from the usable container viewport; its child does not subtract the global keyboard frame a second time. Navigation content uses the space reserved by that inset instead of adding a duplicate dock-height spacer. Existing draft, attachment, selected model, tool authority, and morph animation ownership are unchanged.

The original normal/XXXL UI journeys remain intact. Additional assertions require a nonzero focused editor, a hittable launcher, and placement above the actual keyboard before the original panel/navigation/persistence assertions.

Apple reference: https://developer.apple.com/videos/play/wwdc2021/10021/

Separate full Phase 2 run 44222114455 built the app successfully, then was canceled during the simulator step before a unit result bundle was produced. Its job timeout was 240 minutes and elapsed time was about 52 minutes; no timeout/concurrency cause was established from GitHub annotations. Unit/UI/Motion acceptance remains NOT_RUN for that run. Empty performance metrics do not count as a performance pass.
