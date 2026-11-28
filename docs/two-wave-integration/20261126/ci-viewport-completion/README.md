# Original UI viewport completion

Status: portable implementation checks passed; current-source native execution remains pending.

The original affected plan selects 77 unit selectors and 10 UI selectors. The existing Morph suite contains six wide methods and two compact methods. Every one of the six Sidebar methods asserts a real window narrower than 640 points. A single iPad run cannot satisfy those original assertions.

The ui_viewport_cohorts.json profile maps those 14 actual source methods. The planner checks the complete method membership of each mapped source file before producing a plan. It preserves every unrelated selector. A new method in either mapped suite requires an explicit viewport assignment. The historical 87-selector plan is a regression fixture, not a hard-coded limit in the planner.

## Same build, two original executions

The original build-for-testing and unit prepare/seal/admit path remain intact. The UI stage resolves the same admitted xctestrun, binds the original app, UI runner and test bundle bytes, and invokes original test-without-building for each cohort. It verifies the descriptor and product hashes again after both cohorts.

The wide cohort contains eight unchanged suite/method selectors plus the six wide Morph methods: 14 selectors. The compact cohort contains the two original compact Morph methods and six original Sidebar methods: eight exact methods. These 22 selectors preserve the obligations of the original 10 UI selections; they are not a claim of 22 total native test cases.

The second device is created and booted through the existing selector and ownership receipt code. It has a separate UUID and receipt directory. Original NativeScript and ScriptUI fixtures remain staged on the wide device. The compact methods use their original app seed/launch paths. Original timeout allowances, XCTest assertions, live-provider exact-selection restriction, native-log checks and video obligations remain present.

Both result bundles and native exit statuses are retained separately. A failed first cohort cannot be replaced by the second cohort's success. Missing or skipped required compact methods fail the union coverage check. This is execution membership evidence; original xcodebuild exit codes remain authoritative.

## Verification and limits

The final portable run passed 51 tests: 13 new viewport/product checks, four existing simulator-selection checks and all 34 current cache/CI optimization checks. Both changed original shell blocks passed Bash syntax checking. The new test module is included by the existing Scripts/CI/Tests test_*.py discovery gate.

A first expanded check was accidentally run as the remote root account and failed the repository's existing Git ownership check. Re-running the identical checks as the established worktree owner passed. No global Git trust policy was changed. An earlier development test expectation was corrected to match the existing containment helper's precise error; production containment was preserved.

The retained Mac FormatVersion 1 descriptor confirms only the native field shape used by the helper. The future CI run must still generate current-source product and test receipts.

This work does not execute or replace paired-product acceptance. The original 29 Hanlin paired cases and 25 standalone MiniApps cases require their original two-app installation, shared AppGroup, authoring fixtures and image server. Nor does simulator coverage replace the separate device release IPA/signing gates.
