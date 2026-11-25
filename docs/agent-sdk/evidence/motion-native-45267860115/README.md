# Original retained-content Motion B — run45267860115

**FAIL.** The original B case executed on frozen source35bfa9509ed4660d2c189b1935ed7725d0bae9f2 and failed the unchanged collapsed-content accessibility check at line121 after44.48762595653534seconds. The prior rapid-reversal assertion was not reached.

[Native run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45267860115): job138019456762, hosted runner1000024953,21:15:53–21:39:41UTC (1428seconds). One dispatch, one finite watcher, one terminal acquisition; collector completed21:40:26UTC.

| Scope | Status | Original evidence |
| --- | --- | --- |
| Owned simulator readiness | PASS | Native bootstatus returned0 after161.712s within300s; no recovery. |
| Selected SDK build and admission | PASS | TEST BUILD SUCCEEDED;8 resolved dependencies/6 resource bundles; exact original Equatable1.4.1 admitted; automatic resolution disabled during build/test. |
| Initial collapsed state and first expansion | Executed before failure | Original native log checks collapsed state, taps Thinking, checks expanded geometry and finds proof-summary. |
| Prewarm collapse geometry | Executed before failure | Second tap synthesized40.18s; collapsed predicate succeeds41.61s. |
| Collapsed summary absent from AX | FAIL | At41.88s staticText still exists; unchanged line121 XCTAssertFalse fails. |
| Baseline exact callback count | NOT_RUN | Failure precedes receipt/assertion. Two prewarm tap operations appear in the log, but exact callback count is not established here. |
| Triple burst, gaps, intermediate height | NOT_RUN | No burst was requested. No new-source reversal outcome is inferred. |
| Later presets/nested state/count/drag/persistence/invalid-value/Reduce Motion | NOT_RUN | Original continueAfterFailure=false stops at line121. |
| A/C/D | NOT_RUN in this run | B is the only selected identity. C native+visual PASS remains historical9575 proof. |

The original component retains its accessibilityHidden(!isExpanded) and hit-testing guards on the custom layout while the child remains mounted after animated collapse. The failure establishes unsatisfied collapsed AX absence; it does not by itself distinguish propagation from timing/caching. One authorized [read-only original attachment export45272858701](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45272858701) is pending. It builds/boots/tests nothing.

Xcode subsequently logged a runner restart and an empty restarted suite. Those lines do not replace the single failed44.4876s case or prove a product crash. The raw result remained finalized/readable/archived.

## Source and integrity

Only the reviewed retained-content component and approved25→35minute job envelope differ from the earlier selected source. Original tests/fixtures/runners and native600/720s allowances are unchanged. All401 protected inputs and the full build workflow match central9c1428; source equality does not change the native outcome.

Artifact14864559913:58,170,086bytes, SHA25699ba9280bb2db635ed1932cbe676ab7a9a27916b8b1aa6389fe4af67223d46a5; API size/digest and ZIP CRC PASS,52members.
Motion.xcresult.tar.gz:36,752,079bytes, SHA2568b686fcdd372aa611eebdbb226bf34ffdc9356ddeeb2ebed034290148dab8d76; FINALIZED_READABLE_ARCHIVED.
Full originals remain at /mnt/development/projects/worktrees/hanlin-sdk-motion-b-retained-20261123/build/motion-b-retained-20261123 and in the GitHub artifact. The collection receipt hashes all original members. Large source/video/xcresult archives are not duplicated in Git.

Measured phases: preflight423s, resolution193s, build534s, test213s, results16s. No infrastructure timeout. Recorder finalized at its120s timer; it covers the beginning of the XCTest run, not complete-scenario acceptance.

A+C stays on hold. Diagnose the original accessibility boundary while preserving retained state, geometry, animation, test bodies and thresholds. No assertion weakening or new test rerun is claimed.
