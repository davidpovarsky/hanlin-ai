# Original MCP11 native result and reconciliation repair

## Actual result and scope

The original GitHub route executed the unchanged eleven `HostMCPWireComparisonTests` methods on source `fe0001ac868339d0825d1cc3d07f8383341d163d`. The native command exited zero. There are exactly eleven method starts, eleven passed method terminals, and one eleven-test suite summary. The original source/lock guard recorded `sourceUnchanged: true`; no stop reason was recorded. The native suite took 148.227 seconds. The two original 120-second large UTF-8 controls passed in 82.052 and 66.123 seconds. The recorded toolchain was Xcode 27.2 / Apple Swift 6.4.2.

This qualifies only the original package comparator scope. Real application MCP transport, rendering, persistence and other application/OS gates remain separate.

**The original GitHub workflow and controller concluded FAILURE. That outcome and its raw receipt remain unchanged.** The supervisor incorrectly counted Swift Testing's `Test run started.` header and final `Test run with 11 tests in 1 suite passed` summary as method events, yielding twelve starts and twelve terminals. The native methods themselves passed.

The actual run is [46042428539](https://github.com/davidpovarsky/hanlin-ai/actions/runs/46042428539), job 140653254209. The complete original six-member artifact is retained byte-for-byte in `original-mcp11-artifact.zip` and verified against GitHub's SHA-256 digest, size and every ZIP member CRC. It contains the unmodified full native log, failed controller receipt, source/capacity binding, vendor verification, preparation and outer failure record.

## Source correction

Source commit `8905ee559c0ed8c8d8c86f3f86a5995864108dc9`, based on the executed source, changes only two regular-expression literals in the original supervisor. They exclude the recognized run header/summary from per-method counting. The original controller bytes are recovered by inverting those two literals. Native argv, source/pin/cleanliness guards, process ownership, cleanup, deadlines, all eleven original Swift tests, and the sixteen existing portable supervision controls remain unchanged.

The unchanged native command is:

```sh
/usr/bin/swift test --package-path Packages/HanlinAgentSDK --filter HostMCPWireComparisonTests --jobs 2
```

The original 3,600-second supervisor envelope, 60-minute CI job ceiling and both 120-second Swift test limits remain unchanged.

## Controls and retrospective qualification

A byte-exact 2,046-byte terminal slice of the actual native log is the new regression fixture. The positive control fails against the original parser. All six corrected CI-discovered control methods pass, covering the actual transcript plus missing/duplicate/unexpected methods, failed/skipped results, absent/incorrect/duplicate/failed/malformed summaries, nonzero native exit, an existing stop reason, and all four original source guards. The complete original control outputs and receipts are retained, including the expected original-parser failure.

The separate retrospective reconciliation runs the corrected, unchanged-count logic over the complete original native log. It verifies the exact six recorded source trees and six source/pin hashes against immutable Git source `fe0001ac`, and preserves the historical after-run source guard. It does not launch Swift or create new native results. The root's independent source/result review is recorded separately.

All three changed CI/control/fixture paths have zero intersection with the accepted 396-input SDK manifest. No product source or binary was changed. No second native execution was performed.

`source-validation.json` binds the correction and original-byte inverse. `retrospective-native-reconciliation.json` records the qualified native scope separately from `original-workflow-outcome.json`. `artifact-verification.json`, `encoding-map.json`, and `manifest.json` bind all retained evidence bytes.
