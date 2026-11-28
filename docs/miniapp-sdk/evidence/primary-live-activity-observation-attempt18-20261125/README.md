# Live Activity content observation — attempt18

## Actual diagnostic result

The separate AI diagnostic on frozen source f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51 and historical SDK18 finalized 21 executed cases: 19 passed, 2 failed, none skipped. Six individually selected Swift Testing bodies were absent; the original expected count remains 27, so this is not a completed AI27 gate. The earlier paired MiniApps result remains 22/3/0, with its paired AI27 not executed. These executions are not combined into a new paired PASS.

The exact final summary identifies one Live Activity issue: the test immediately read revision 1 where revision 2 was expected at original line146. The retained contiguous case log contains only that issue. The test continued through the later immutable snapshot load, Count9 and m9 assertions and lifecycle operations without another recorded issue. The original load method uses the supplied snapshot reference/hash, not mutable widget state, so the observations support a publication race between update completion and the immediate property read. No production update failure is asserted from this evidence.

The other diagnostic failure concerns the separate repair UI, and the six missing selectors remain separate corrections. Neither is hidden or repaired by this change. Original warnings remain in the exact summary.

## Test-only correction

Source commit ebf40f335fe8af5cdc61c910ee722922f5fed330 changes only AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests.swift. It observes the original ActivityKit contentUpdates sequence and also accepts an already-published exact state. Activity access and iterator operations stay in the MainActor observation task. The task checks cancellation before accepting its current or streamed state. A sibling deadline task bounds a missing observation to five seconds using the existing project's throwing-task-group pattern, and defer cancels the sibling work.

The expected revision remains exactly 2. One observed, explicitly Sendable ContentState is used both for that assertion and for the immutable snapshot load. Count9, m9, end, inactive-instance rejection and reconcile assertions are unchanged. All 22 expectation calls and all 3 original test functions remain. No production implementation, fixture, selector count, package or vendor source was changed.

This is asynchronous observation, not a fixed delay followed by an assumed pass. The API's actual cancellation and delivery behavior still needs the planned native execution. Source review does not prove a hard SDK delivery-time guarantee.

## Original references and limits

The source-bound A2UI and split-component helpers already use a throwing task group, a cancellable deadline task and cancelAll. Relevant exact snippets and full source hashes are retained.

Apple documents contentUpdates as the original way to observe Live Activity content changes and directs clients to asynchronous update sequences to keep content in sync:
- https://developer.apple.com/documentation/activitykit/activity/contentupdates-swift.property
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities

The retrieved update documentation does not promise synchronous property publication at await return. This record does not invent an SDK signature, inspect private ActivityKit implementation, or claim compiler acceptance of the new helper.

## Evidence and pending validation

The frozen packet receipt, exact summary/nodes, selected command, original verifier output, diagnostic state and earlier paired state are copied and independently checked. The case log extract preserves its original contiguous text and binds the complete 80,898-byte source log by SHA-256; the complete log and 120-file packet remain at their retained transfer location. This is a bounded evidence copy, not a duplicate of the 56 MB packet.

The root reviewed the initial full diff and received the final commit. The independent status-reporting peer reviewed exact final source SHA 7d6b159d580636269daf67f6ed04634d586b94d07c960bd099cc9c5f4da9e164. Only source/readback/diff checks ran in this lane. Actual Swift6/ActivityKit compilation and the original affected test remain NEEDS_TEST. The normal native owner retains sole execution ownership.
