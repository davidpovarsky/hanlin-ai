# MiniApps startup inner-await diagnostics

Source commit: `b4ee5612f005caa1a570749ecbd0a7c8b545901d`
Parent: `e86e779d5d4bf85db3c9802e569c032283515ad6`

The original first MiniApps preferences UI case failed while the app displayed
`Loading apps…`. Its own process trace reached extension-snapshot refresh without
returning before the original 40-second preferences-button assertion failed.
Another restore in the same process returned. That evidence does not identify
the pending inner operation or prove a deadlock.

This four-file candidate adds DEBUG/HANLIN_TESTING observations around the
existing snapshot artifact/provider awaits, durable publication, LiveActivity,
Spotlight reconciliation and Capture appContext read/update. It records the
original Spotlight owner/coalesced return, write/predecessor chain, actual
delete/index/value awaits and the actual reindex callback return boundary.

## Preservation and scope

No Task, asynchronous operation, timeout, delay, cancellation, actor hop, guard
read, test or assertion is added or replaced. Original runtime ordering and
callback acknowledgment behavior remain. Debug-only extra state consists of two
optional observation-UUID strings; added Task captures are only strings and a
monotonic start time. No entity/document/camera/user payload is added to logging.

With both DEBUG and HANLIN_TESTING disabled, Platform and Entity projections
recover their originals directly. Six Spotlight and two Capture formatting
inverses recover the remaining whole original Release projections byte for
byte. The completed structural qualification and independent W1 review are
retained here. They are source evidence, not native compilation or runtime tests.

R1's new log prefixes used a category excluded by the existing paired failure
collector. R2 changes only these new debug loggers to `MiniAppsCatalog`, matching
the unchanged collector. Original restore logging, the 15-minute capture window
and 30-second diagnostic cap remain intact. The exact final raw patch is retained
losslessly as `source.patch.gz`; its expanded SHA256 is
`1f0d9cc9c0f1deb1d94c6e252d71403ca9e05e3f5e3dfab79b76ab83eea23d3b`.

## Interpretation limits

Only write-to-predecessor and coalesced-call-to-owner UUIDs are explicit links.
Nested callback/helper/restore and reconcile/reindex/write relationships still
require PID/time/source-order inference under overlap. These UUIDs identify
observation spans, not native OS operations or committed catalog revisions.

`returned` records that the original call returned; it does not imply a non-nil
value or error-free internals in a nonthrowing helper. The predecessor retains
its original `try?` behavior. Generic `exit` is not success. `ack.return.ready`
marks the Swift callback's return boundary, not OS receipt of acknowledgment.
Logging may perturb timing and OS record delivery must be observed.

## Remaining qualification

All four changed files are current SDK396 inputs, so the old producer
fingerprint/archive cannot automatically qualify the new source. None is a row
in the unchanged 259-file widget upstream provenance manifest.

Native compilation, the original first preferences case and final producer
qualification are **NOT_RUN for this candidate**. The diagnostic preserves the
original selector and 40-second assertion:

`HanlinMiniAppsUITests/MiniAppsCrossAppPreferencesUITests/testAppleStyleEditorAddsFavoriteWithNativeEditControls`

No causal repair or native PASS is claimed. Integration and native execution
remain separately owned. This proof contains no private task records or other
project material.
