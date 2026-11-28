# Real OS notification ingress failure and localized correction

This is an immutable **FAILED** observation of the original case, followed by a source correction that was **not yet compiled or rerun** when this packet was written. It does not replace the authentic full52 or NS5 passes and does not claim that the corrected build passed.

## Observed execution

The original selector was `HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines`. On 2026-11-25, the isolated recovery controller ran once from 20:43:13.771394 to 20:47:06.338726 UTC. It used the unchanged original prebuilt xctestrun, worker, UI source and three fixtures; compiled source remained **d4a0b115b106d4250ea40ad66153d5156847a07c** with the previously authenticated25 prepared files. Carrier7f46 and correctiondff are not relabelled as that compiled binary.

The new owned iPad simulator was **2EFAD83F-45A2-4A8B-B326-16B83BC56DA9**, iOS27.0 build24A434. After real notification authorization, XCTest generated a fresh run identity and the observer bound the actual current app/runner/AppGroup containers. Expo's simctl push returned0 at20:45:49.326637 UTC. At20:45:49.322674 UTC the actual app logged `[NotificationIngress] notification_event_not_enqueued`. The callback therefore reached the app.

The worker timed out at20:46:59 waiting for a terminal OS-ingress receipt. The original XCTest result is **0 PASS /1 FAIL /0 SKIP**,168.809seconds, original source line1598. The exact event was `1a36dea1-72a1-4ba4-b23d-f36ad3f693b5`. In the current actual AppGroup, both ResumeQueue and Receipts were absent. NativeScript, duplicate and intentional action-failure phases were not reached. A successful push alone is not a successful application invocation.

Cleanup and source checks were clean; all owned process groups were absent and the simulator was Shutdown. New preparation1.332704125001328s plus actual execution232.5675223750004s totals233.90022650000174s. The independent900s observation remainder was666.0997734999983s. The original897.3027506670041s OS history is unchanged.

## Causal diagnosis and correction

The exact790-byte APNs payload supplies plain JSON parameters with challenge, ordinal41 and Unicode. The event decoder passed that ordinary JSON to HanlinJSONValue's internal Codable decoder, which requires a tagged object with a type field. The actual callback marker plus original payload and decoder identify rejection before enqueueing. Delegate registration worked; no delegate or queue rewiring was required.

The reviewed correction is commit **dff3b45c99a57bf8fe8ec721db3fa1fafce7134b**. Only the external decode(userInfo:) and userInfo() boundary methods convert plain JSON through the existing canonical JSON helpers. Internal Codable stays byte-identical. Three new regression functions cover independently authored null/scalar/array/object parameters, ordinary type/value user fields, external plain serialization, internal tags and strict missing/malformed envelopes. Existing test bodies, original UI selector and worker are unchanged.

At this packet's timestamp the correction is committed but not compiled. The event source is one of SDK19's235 declared source inputs, so dff must not be described as retaining all235 SDK19 source hashes. A correctly regenerated SDK and a genuine native rebuild/affected verification are follow-up obligations.

## Evidence retained

The terminal and ingress directories contain all83 original stored members with original receipts. Stored hashes and decompressed hashes were independently checked during assembly. Diagnostic context is a verbatim17-line excerpt with its original36,622,902-byte stdout SHA256. The full diagnostics packet and source stdout remain retained on Oracle; this Git packet includes its exact receipt and causal excerpt.

The complete original xcresult is retained separately at:
`/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/notification-os-recovery-v1-xcresult-archive/NotificationOS.xcresult.tar.gz`
(89,006,891B; SHA25607720ea7537ea3705c7baf8d41acd1e837c57948192af0e5dec06cca5413192c).
Its116-member source manifest and both independent stream verifications are included. The archive is not duplicated into Git. The preparation authorities and exact executed controls are included; all44 compiled product rows matched before and after the recovered preparation. Earlier missing-checkout cause remains unknown.
