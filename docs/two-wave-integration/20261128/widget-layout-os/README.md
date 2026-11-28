# Medium Widget control-layout acceptance

Source: 0c6ad155905f30273d3dfac2b5071ce14970b6d0, based on 9ee23af8c3556502ba6da8ba7fccd05a8c35adb1.

**Status: independently reviewed source; native compilation and the new OS case are NOT_RUN.** This adds one explicit acceptance pilot and changes no widget, runtime, fixture or product behavior.

## What the additional case requires

The shipping importer and actual Home Screen gallery create one fresh, named Medium Matrix widget. The host must be observed terminated. The test re-reads the saved instance name before credit, before and after actions, after each rotation, and before removal.

The unchanged Matrix defines this exact sequence:

| Observation | Actual action or orientation | Required native values |
|---|---|---|
| 0 | Initial portrait placement | count 0, enabled false |
| 1 | Native Toggle to true | count 1, enabled true |
| 2 | Native Add | count 2, enabled true |
| 3 | Native Refresh | count 2, enabled true |
| 4 | Landscape left | Unchanged final state |
| 5 | Portrait | Unchanged final state |

Each action must commit exactly one new native revision and UUID. Refresh cannot pass from unchanged visible values alone. Native UUID letter case is preserved; case-equivalent replay is rejected. The UI action ID is an observation identifier, not the native WidgetKit nonce. Their association uses the uniquely admitted variant, real tap interval, subsequent native commit and unchanged other-instance state digest.

Every observation retains actual AX and PNG bytes, configuration, window/widget/screen frames, and the count-marker/Toggle/Add/Refresh frames. Those four elements must be present and hittable, finite, contained in their actual widget/window, and pairwise nonoverlapping. The native cache must match the exact family, instance, program and state. Initial rendering must follow the real Add Widget action; action rendering must follow the beginning of its observed tap interval. A synchronous result before tap() returns is valid. The tap interval and Add Widget timestamp cannot be rewritten after admission.

Orientation requires effective AX and PNG geometry. Rotation may reuse the verified unchanged timeline. Cleanup removes only the freshly reverified own widget through the system confirmation and restores the prior observed orientation. Missing or ambiguous identity, cleanup or restoration cannot produce acceptance.

## Preservation and integration

The five source paths and exact Git objects are recorded in qualification.json and source-seal.json. Removing one UI insertion recovers all 37 original methods and every original helper byte. The runner and dispatcher also recover byte-exact after removal of the documented additions.

The new scope is miniapp_widget_layout_os, selecting only testMiniAppsMediumWidgetNativeControlsStayVisibleAcrossStateAndRotation. Its new case has a 420-second allowance. Original 2100-second command/observer bounds and the 210-minute workflow cap remain unchanged.

The separate workflow proposal contains only the manual choice, original Widget producer condition and always-upload condition. It is reserved for root publication; it is not included in the source donor.

An actual git apply/check against a new file projection of root 5f827bac46543271991668a089830650893cd72d passed. Removing the insertion recovered that entire current UI file, including the separately reviewed Shortcuts helper. This was a projection check, not a root-worktree mutation.

All Matrix and original 25-output recipe bytes are unchanged. Static intersection with the accepted 396 SDK source paths is zero. No new SDK or Host pass is claimed.

## Portable qualification, including the first failed run

The complete current control set has 18 qualified methods. Four affected methods passed in the latest selective execution; 14 unchanged methods reuse their actual matching prior passes. This is not described as a fresh 18-test run.

The first execution ran 17 methods: 15 passed; two methods produced four error subcases because the new controls expected ObservationError for malformed UUID text while the original parser correctly raised ValueError. The existing dispatcher catches and records that rejection. Only those two test expectations were corrected and rerun. A later source audit aligned the new native-nonce comparison with the original executor's valid uppercase UUID spelling; three affected controls and one new compatibility/replay control then passed.

portable-qualification.json binds every method, command, result, source/AST hash and scope of reuse. All three raw logs, including the original failure, are retained losslessly as gzip. These are parser/evidence controls; they manufacture no OS receipts or screenshots.

## Independent review and remaining work

The root review covers the reader, controls, original state/Refresh semantics, source/fixture admission, runner inverse and three-location workflow proposal. W1 independently reviews the Swift UI insertion, physical configuration, window/control query, tap timing, cleanup and orientation lifecycle. Both receipts are included verbatim. Their referenced larger mechanical packets remain retained by immutable hashes; they are not claimed to be copied here.

This pilot covers one Medium iPad Home Screen layout and four measured elements. It does not qualify RTL, appearance/contrast, Today View portrait, Lock Screen accessories, other families, the full Progress/Gauge/Chart/timer/link/image inventory, VoiceOver, broader failure/instance matrices, or physical devices. Original failures remain failed, and the full Tasks 03/08 requirements remain open.

The new Swift source, actual placed-widget locators, complete OS case and screenshot review still require the original native route. No native run, public dispatch or test-budget change was performed by this source/proof work.
