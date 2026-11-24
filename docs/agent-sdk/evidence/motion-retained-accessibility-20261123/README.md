# Explicit accessibility boundary for retained disclosure content

## Native evidence and bounded cause

Original B45267860115 at35bfa950 FAILed at the unchanged collapsed-summary absence assertion, line121, before the rapid burst. Read-only export45272858701 preserved the actual video and activities. The reviewed video shows expanded/actions1 at37.8s and collapsed/actions2 at40.5s, with no visible details after collapse. Original native activities query the summary after the collapsed geometry predicate and report that it still exists. Both observed frames use v1.relaxed with motion enabled. No full AX hierarchy was exported; the activities prove the query result, while video establishes visual collapse separately. The previous outer custom-Layout accessibilityHidden guard is insufficient in this retained-child configuration.

## Exact production change

Two modifiers are added to the existing child VStack inside HanlinAnimatedDisclosure:

- accessibilityElement(children: isExpanded ? .contain : .ignore)
- accessibilityHidden(!isExpanded)

The real retained child now owns an explicit accessibility container. Expanded content retains its individual accessible children in a container; collapsed content ignores its child accessibility elements and hides that container. The outer existing accessibilityHidden remains. These are modifier-value changes on one persistent VStack, with no conditional visual subtree, changing view ID, remount, height/frame/layout change, timer or alternative content.

Apple defines contain as retaining child elements under a container and ignore as hiding child elements:
https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior
https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)

## Actual call sites and preserved behavior

HanlinActivityDisclosureStyle, HanlinInlineToolApproval, and public HanlinMotionDisclosureStyle all continue to use the same component and bindings. Expanded child labels/actions stay individually navigable; collapsed child actions are excluded at the actual retained container. Host visibility propagation, approval callbacks/request identity, DisclosureGroup ownership, mounted/progress state, natural-size geometry, zero-height clipping and hit-testing guard are unchanged. The previously documented retained-row lifetime of already-opened child state/tasks is unchanged. Never-opened laziness and existing no-motion/onAppear settle behavior are unchanged.

## Verification and affected scope

Linux Swift syntax parse PASS; this does not typecheck SwiftUI or prove native accessibility behavior. Removing exactly the two added modifier lines restores the executed35bfa component byte-for-byte. All tracked original Motion fixture/measurement/test/runner files and other Motion sources, plus the two external call sites, are byte-identical to35bfa; hashes are recorded.

Native acceptance of this candidate is NOT_RUN. Root review precedes one original B-only run with the original collapsed-absence, exact callback/geometry, burst and later state/preset/Reduce Motion predicates and timings unchanged. A and changed-source C remain required but on HOLD; diagnostic D is not replayed. Existing historical PASS and executed FAIL records remain unaltered.
