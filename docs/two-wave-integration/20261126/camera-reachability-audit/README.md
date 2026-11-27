# Camera reachability audit correction

The accepted camera wrapper declares actor-isolated LockedCameraCaptureExtension conformance. The source auditor still required its older unqualified declaration and blocked original Host pretest before any Host test ran.

Commit 0456adbe395cde2fb986cf058c4a9497c38d1d21 changes one exact anchor string to include @MainActor. Every other auditor byte and the exact-match failure mechanism are unchanged. No native wrapper, runtime, package, fixture, dependency pin or original test changed.

## Executed checks

- The original pre-correction reachability command reproduced the precise anchor failure.
- Original reachability generation and check passed all 100 source routes.
- All seven existing exported-bundle topology/coverage regressions passed.
- An in-memory missing-actor negative control was rejected by the original build function.
- Generated routes, status/acceptance boundaries, target identities, entitlement declarations and library/local presentation records are unchanged.

The complete native package pass at16b4 contains 58 methods /79 invocations, zero skips and all original parameter values. Its raw reconciliation reference is in receipt.json. This audit-only delta changes none of those package/fixture/pin inputs, so no duplicate native run is claimed or required for the anchor change.

The canonical SDK consumes the regenerated reachability JSON. Current-source Host/SDK preparation still belongs to the native owner and remains separate from these source checks. No OS surface, signed IPA or physical-device acceptance follows from this source map.

Independent built-in agent /root/wave1_chat_sdk approved source0456, verified all102 SDK source hashes and126 anchor hashes/lines, and confirmed that the complete delta from the accepted native16b4 source is audit/docs only. Its original receipt is retained as independent-source-review.json; no duplicate tests were executed by the reviewer.
