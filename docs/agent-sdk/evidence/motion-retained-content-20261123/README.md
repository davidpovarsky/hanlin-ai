# Preserve the original disclosure content across animated reversals

The original B failure at `9575dd15e816009e11d84ab7f4e21b45cb67c5e8` delivered all three rapid callbacks with effective motion enabled, but captured0/0/0-point pre-action heights. The original encoded frames show all5 actions before the first visible summary in the reviewed sequence. The previously grouped row did not fix this. [Exact native evidence](../motion-native-45248270552/README.md) remains FAIL; the mounting/layout explanation is a source-supported hypothesis awaiting the affected native test.

## Minimal production change

`HanlinAnimatedDisclosure` keeps content that has already mounted during animated collapse and reversal. It no longer destroys the complex child when the collapse animation finishes. That allows a following reversal to reuse the existing measured hierarchy. The obsolete revision state and completion-cancellation bookkeeping are removed because there is no longer a completion callback.

The original animatable layout, finite natural-height guards, curves and durations are unchanged. Collapsed height remains zero, clipping remains enabled, hit testing remains disabled and accessibility remains hidden. The first-ever expansion still mounts lazily. Existing `settle()` assignments reset mounted/progress on appearance and whenever motion becomes nonanimated. There is no timer, test-specific delay, alternate renderer, global cache or copied component.

## Actual call-site and lifecycle assessment

| Existing call site | State/resource implication | Existing boundary preserved |
|---|---|---|
| `HanlinActivityDisclosureStyle` used by original agent activity hierarchy | Previously opened nested text/details state and finite text ScrollViews remain mounted while the row is retained. Projected details remain equatable; never-opened children remain lazy. | The content's `hanlinActivityBranchVisible` remains inherited visibility AND expansion. Shimmer and live activity timelines already obey that environment. All links/actions remain hidden and non-hit-testable when collapsed. |
| `HanlinInlineToolApproval` | The tool name and finite review text ScrollView retain layout/state during collapse. | Request identity, explicit review/allow/deny callbacks, decisionSubmitted guard and `.id(requestID)` ownership remain unchanged. Retaining details neither grants permission nor executes tools. |
| Public `HanlinMotionDisclosureStyle` | Generic host-provided child identity persists after an animated collapse. No in-repository production consumer of this exported style was found. | Existing native DisclosureGroup state, header interaction, animation and accessibility ownership remain unchanged. Hosts still own child work/lifetimes; arbitrary custom child tasks can remain active until view detachment rather than stopping on animated collapse. |

The deliberate tradeoff is retaining memory/state for already-opened content while SwiftUI retains its row, in exchange for avoiding repeated remount work during normal collapse/reversal. The component adds no cross-row cache or external task. LazyVStack/Host ownership and the existing onAppear settle continue to govern reattachment. Native memory/performance improvement is not claimed from source inspection.

## Verification and affected scope

- **PASS**: Linux Swift syntax parsing of the changed original component. This does not compile SwiftUI or establish Apple runtime acceptance.
- **PASS**: byte equality for the geometry/layout implementation, collapsed visibility guards, all original presets, preferences, test bodies, gesture/measurement source, native runner and three call sites. Their exact hashes are in `source-verification.json`.
- **NOT_RUN**: native acceptance of this changed production component.
- Next reviewed experiment: one original B-only run using the already-published exact selector. It directly tests rapid reversal and, if the early assertion passes, the original nested state, type/count, drag, persistence and actual Reduce Motion scenarios. No assertion, gap, wait or animation timing changes.
- A remains required because repeated cycles are unaccepted and this lifecycle path affects them. C's previous native+visual PASS remains authentic at9575; this change affects C's final collapse lifetime, so it is not silently relabeled as acceptance of the new component. Any subsequent original C validation must target that changed scope; no separate diagnostic D replay is needed to replace original B.

No native dispatch is included in this commit. Review and a frozen qualified source precede the single affected B run.
