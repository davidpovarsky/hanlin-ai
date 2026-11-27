# Failed terminal activity titles

The original canonical presentation test exposed a real behavior mismatch: the activity correctly became failed, but an explicit execution title such as “Invalid arguments” was replaced by the generic operation name. The original failing test is unchanged.

Only the failed/cancelled title branch changes. A failed execution may retain its explicit sanitized title when it is meaningful, is not a generic or approval label, differs from canonical running/completed labels, and was not retained from an earlier nonfailed step with the same actual call identity. Cancellation keeps the existing operation fallback. Raw errorDescription is never substituted into the title. All other title paths and helper bodies remain unchanged.

Historical running-label rejection requires the earlier same-call step to be present. The Composer sorts and groups those actual steps without discarding either one in the regression. Missing identities do not establish shared history. Six additive native test methods cover retained running labels, canonical lifecycle labels, absent call identity, cancellation, generic/approval labels and unsafe text. They use the existing original target; they have not yet executed natively.

The exact accepted 392-input SDK manifest has no changed-path intersection. This is source qualification, not an application-build or native-test PASS.
