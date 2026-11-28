# Notification descriptor admission diagnostic

The original notification run 46128022331 on 5facdb20 completed its fresh build-for-testing, install and launch, then rejected the descriptor candidate count before invoking XCTest. Its evidence did not retain the actual count or names, so zero and multiple descriptors remain distinct unresolved possibilities.

This change records bounded metadata only on that existing failure branch. It retains the complete already-computed count, at most 64 candidate lstat records, six fixed product paths with a parent-directory gate, and references to the original build journals. It does not read descriptor contents or recurse through products, launch commands, wait, select a preferred descriptor, or change the original admission.

The attempt-owned diagnostic uses exclusive creation. An existing file/symlink or another persistence failure cannot overwrite evidence or replace the original admission error. All original source/product/target/selection checks and the 1200/650/600 second limits remain unchanged.

The original focused notification module ran once: 25 controls passed, including all 23 unchanged old controls and two new bounded-output and failure-preservation controls. The original missing/ambiguous negative case emits an expected diagnostic between its unittest start and terminal line; the separate reconciliation binds all 25 actual identities without rerunning the suite.

The independent Mac review approves the source change only. Actual notification OS delivery remains open. The separate compiler-repair review retained here supplies original terminal byte/SHA/CRC readback verification for both failed routes; it is not a notification acceptance result.
