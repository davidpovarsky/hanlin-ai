# Canonical Widget catalog compatibility

The read-only Widget observer now admits the canonical partial compatibility
value alongside supported. This changes one predicate in widget_facts.
All other identity, kind, engine, context, enabled-state, generation, runtime
policy, publication, program, and artifact-digest checks remain unchanged.

The regression loads the unchanged stored-registry semantic fixture in
HanlinCanonicalEntrypointProjectionTests.swift. Its Widget row is partial.
The filesystem publication and program used by the portable controls are
constructed from the existing Matrix fixture metadata; they are not a recovered
device snapshot.

## Actual portable evidence

The original reader rejected the canonical row at the existing compound guard:
one test, exit 1. With the one-line correction, all nine focused tests passed:
six unchanged Widget recovery controls and three new CI-discovered controls.
The new negative control covers 18 invalid catalog mutations and one corrupted
artifact digest. Both complete stdout/stderr streams and the patch are retained
losslessly as gzip files, with original-byte hashes in encoding-map.json.

Independent source review verified a byte-exact inverse of the predicate change,
all 38 other reader function ASTs, the unchanged original control file, and the
new controls. Independent proof review reconciled the actual original rejection
and candidate nine-test pass without rerunning them.

## Scope and limits

No product/runtime code, fixtures, native test assertions, selectors, time
budgets, workflows, or version pins changed. Neither changed path belongs to
the current 396-input SDK manifest. Native execution was not performed for
this observer correction.

The earlier hosted recovery run reached the compound Widget guard, but its
rejected catalog row was not retained. The canonical mismatch is reproduced;
it is not established as the sole cause of that native failure. The historical
failed run remains failed.
