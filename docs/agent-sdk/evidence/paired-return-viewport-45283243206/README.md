# Original paired return failure and compact transcript backdrop

Source run: https://github.com/davidpovarsky/hanlin-ai/actions/runs/45283243206 (attempt 1), source 4cfa52348e80cf635caf04c541fd84ee1ddb50bd.

This is a targeted derivative of the single original artifact acquired by the paired owner. It is not a new native execution. The original run/artifact/source and one-acquisition receipts remain in ../paired-native-45283243206.

## Executed boundary

testCompanionReturnsActualPrivateValueToOriginalChat failed before review-toggle tap, explicit permission, companion launch or return. Native input and Send did execute. Three original accessibility snapshots (22/24/26) place the review toggle at x81/y355.7/w286/h26, below the transcript viewport x0/y0/w402/h334. The approval container is y346.3/h133.5, while the focused composer is y438/h38. The original request and permission review are not replaced by a stub.

The control exposed by the original Host request is hanlin-tool-consent-allow-remember, disabled before review. The paired test's old allow-once selector would be a subsequent navigation defect; it was not the recorded failing tap. Final snapshot28 shows the original call Not approved and PAIRED_RESULT_NOT_VERIFIED; snapshot29 visually confirms that final state. No actual cross-app result is claimed.

## Independent visual finding

Original video frames at 65,75,100 seconds are extracted from its exact retained xcresult payload. video-extraction.json binds the payload hash, time and output hashes; original-return-activities.json preserves the original event timeline. Send occurs at 63.967–66.511 seconds. At 100 seconds the waiting activity is covered by the bottom gradient.

HanlinChatView unconditionally drew a 120 point gradient that becomes opaque halfway down, even when the compact Host supplies its composer as a separate sibling outside this view. Its transcript clearance is 24 points after 4cfa. The repair adds a default-true showsComposerBackdrop option and passes false only for the existing external compact composer Host. Existing overlay hosts retain the exact original gradient.

This repairs that demonstrated overlay defect. It does not claim to fix the separate absent auto-follow or prove permission controls become reachable. Existing opt-in composer diagnostics now also report controller geometry/policy and scheduling guard boundaries, without recording draft text or tool arguments, changing policy or introducing delays.

## Validation and limits

PASS: syntax parsing of the two affected Swift files and git diff --check.
NOT_RUN: native compilation and visual acceptance of this repair.
FAIL remains the original return case. Its original assertion/deadline is unchanged.
The separate full transfer/rollback PASS remains recorded in the paired original packet; this change does not touch its importer, storage, runtime or transfer flow.
