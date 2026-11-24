# Original Motion B with retained-child AX boundary — run 45278413617

**FAIL.** The unchanged original testBRapidReversalPresetSwitchAndPersistence failed after **25.335636973381042 seconds** at MotionUITests.swift:121, where proof-summary was required to be absent after the settled prewarm collapse. Rapid reversal was **NOT_RUN**.

[Original native run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45278413617) · frozen source d8e4327f6d4097ac5a206f2acf2bf654a7ee9c13 · native job 138056155630 · hosted runner 1000025131.

## Actual result and boundaries

| Scope | Status | Original evidence |
| --- | --- | --- |
| Fresh owned simulator startup | PASS | Native bootstatus returned 0 after 132.747 seconds within the unchanged 300-second readiness budget; no recovery. |
| Selected original SDK build | PASS | Canonical HanlinChatUI source compiled; 8 resolved dependencies and 6 resource bundles recorded; original Equatable pin admitted. |
| Initial collapse, first expansion, summary exposed | PASS for those executed checks | Original log and original video show first expansion. |
| Second tap and settled collapsed geometry | PASS for that executed predicate | At test t=23.12s, collapsed predicate succeeds. |
| Collapsed summary absent from accessibility query | FAIL | At t=23.20s, a fresh query still returns the actual summary; original line 121 fails. |
| Exact baseline callback assertion | NOT_RUN | The original assertion is later. The fresh diagnostic label separately reports actions=2. |
| Three rapid callbacks, exact gaps, intermediate height | NOT_RUN | No burst was requested before the failure. |
| Later nested state, presets, count/drag, persistence, invalid value, Reduce Motion | NOT_RUN | Original stop-on-failure behavior remains unchanged. |
| A, C, D | NOT_RUN in this run | B was the sole selected original identity. Historical C proof remains scoped to its earlier source. |

The local collector completed successfully; its exit code is an acquisition result, not a native test pass. Xcode later started an empty runner suite. That does not supersede the failed original case or, by itself, prove a product crash.

## Original accessibility and visual diagnosis

The already-owned raw result uses Apple's fileBacked2 backend, not SQLite. Local Zstandard decoding of its original Data files revealed the app and XCTest runner consoles. No new native export, build, simulator, or test run was used.

At **22:51:38.125569 UTC**, app pid 23854 supplied a fresh tree whose state labels say collapsed, expanded=false, actions=2, v1.relaxed, and shimmer=true;numeric=true. It still contains the actual proof-summary StaticText, AX ID **4593262880.54**, under container Other **4593264320.53** in the proof ScrollView. The same IDs appear in the earlier expanded tree. The container also exposes the plain source-call2 and source-call3 Text siblings and the nested tool button. This is the retained subtree, not evidence isolated to selectable text.

The XCTest runner's matching query completes at **22:51:38.132 UTC** using that fresh tree. No stale earlier snapshot is needed to explain the failed check. The original logs do not associate these exact IDs with a concrete UIKit/SwiftUI provider class; no such private-framework diagnosis is claimed.

The original video at PTS 10 seconds shows expanded/actions=1 with the original summary and siblings. PTS 11–12 show collapsed/actions=2 with the footer directly below the header and no displayed child details. The contact sheet preserves this limited visual observation; it does not establish rapid reversal or frame timing.

The original owned-sources.tar.gz contains the reviewed component byte for byte (SHA256 bb621c8312e153ac65a963da25ee845a35f46c40ccd13fe66540404f0ad626f2). The actual compile log names that canonical Vendor/HanlinSDK path in HanlinChatUI. A different source checkout or duplicate local component has not been substituted.

Current source retains mounted content after animated collapse. Both outer and inner accessibilityHidden guards are present; the retained inner VStack also changes child policy from .contain to .ignore. Apple documents that ignore hides children and always creates a new accessibility element, whereas contain groups existing children and can modify an existing container:
- https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/ignore.md
- https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/contain.md
- https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:).md

The observed result contradicts the intended dynamic boundary. The framework mechanism is unproven. A constant containment policy with only hidden state changing is a candidate for review; it is not native-validated here. Unmounting at completion would return the subsequent original prewarm/burst sequence to the already observed complex-child remount risk. No timing, assertion, native content, or fallback renderer was changed for this evidence.

## Integrity and acquisition

Artifact 14869368460: **65,448,412 bytes**, SHA256 9a2ce27a851f54a51aced047419b3bb08e3ff05fdb275bc859218c9b8482cd32. API size/digest and ZIP CRC PASS; 52 members.

Motion.xcresult.tar.gz: **40,758,950 bytes**, SHA256 78749ef886ac307f0218a4a3fab11bef905ae384bd492cf9df7b0b4db5515197, finalized/readable/archived. Full originals remain in the GitHub artifact and Oracle's frozen B worktree under build/motion-b-accessibility-20261123.

One dispatch, one finite watcher, one terminal acquisition. Watcher job_5a2701f33a78 finished at 22:53:19.751 UTC. The two complete decoded runtime logs are stored losslessly as gzip; inventory records original compressed Data names/hashes and decoded hashes. Initial payload format hints are not claims of valid JSON or decoded private schemas.

**A+C remains on hold. This evidence authorizes no new dispatch and closes no native acceptance blocker.**
