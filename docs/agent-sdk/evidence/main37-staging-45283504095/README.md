# Main37: original staging failure, 45283504095

[Run 45283504095, attempt 1](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45283504095) at source `4cfa52348e80cf635caf04c541fd84ee1ddb50bd` ended **FAIL before test execution**. All 37 requested invocations are **NOT_RUN**: 26 unit and 11 UI. The original per-method and per-argument selection is preserved in `reconciliation.json`. Its historical partition remains 18 PASS / 7 FAIL / 12 NOT_RUN; this attempt does not fix or reproduce those seven functional failures.

## What the original evidence proves

The full arm64 simulator app/test build and current-product admission passed. The sealed generated xctestrun now resolves the UI target to `__TESTROOT__/Debug-iphonesimulator/AI_Hanlin.app`, including the required suffix. That proves the generated-path repair; UI launch and runtime behavior were not exercised.

Original resource checks passed for 37 copied resources and two byte-identical complete bundle inventories. Localization checks passed for 3,683 canonical catalog values, 177 packaged values and four identical localization bundle inventories across the app and retained extensions. The original runtime signature scan passed. The retained NativeScript visibility receipt remains scoped to metadata; it does not claim execution of a native VM test.

The run's owned simulator booted successfully, and installation of the admitted original app returned 0. The next command, `simctl privacy <owned-UDID> grant calendar com.itorah.chavrusachat`, timed out after 20 seconds and returned 124. The original fail-on-error path stopped preparation before the reminders command and before test-without-building. Unit and UI result exports are absent. The current-product receipt explicitly says `ADMITTED_NOT_EXECUTED`. The system-log diagnostic also timed out after 20 seconds, so it supplies no evidence for a particular TCC-service cause.

No duplicate-class runtime warnings appear in the original job log, but no app/test launch occurred. Runtime single-image identity and the affected Calendar, credential and ShareInbox behavior remain unverified. All eight selected test-source files are byte-identical between the earlier 452650 source and this run; source hashes are recorded individually.

## Custody and publication

The assigned smoke ZIP (artifact 14873545801, 3,462,247 bytes) was acquired once. SHA-256 `caa30774d1c319df49647cb96e35ee4d983c070aee724d55fdf0e7aca0df344b`, all 93 safe unique member hashes and CRCs were verified. The original ZIP stays in the release evidence owner's Oracle directory; this commit contains its complete member inventory and only selected small original receipts. The original 36,472,622-byte native job log was already acquired by the root owner and was reused without another download. Its exact hash and a bounded original failure excerpt are retained.

Prepared Native artifact 14871626421 is **INELIGIBLE** because its producer failed. It was not acquired or published. Final SDK/Host pin adoption remains held. This documentation audit executes no tests, downloads no second copy, and changes no production source.
