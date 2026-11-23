# Constant retained accessibility container — review candidate

**Native acceptance: NOT_RUN.** This changes exactly one production line in the original shared HanlinAnimatedDisclosure: its already-mounted VStack always uses .contain. The existing accessibilityHidden(!isExpanded) changes visibility while the container policy remains constant.

## Why this candidate

Original run45278413617 failed the unchanged prewarm accessibility absence assertion at line121. Its fresh app tree exposes the same retained summary, parent container, plain Text siblings and nested tool button after settled visual collapse. The original compiler input and archived source match the reviewed component exactly. Evidence is preserved in ../motion-native-45278413617.

Apple documents that .ignore always creates a new accessibility element, while .contain groups children and may modify an existing container. Moving from containment to a newly ignored element while simultaneously hiding it introduces a different accessibility ownership policy at each collapse. The observed retained subtree does not follow the intended hiding boundary. A stable containment policy removes that ownership change and preserves the actual children. The private framework cause remains unproven; only the original native B run can accept or reject this candidate.

Primary references:

- https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/contain.md
- https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/ignore.md
- https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:).md

## Preserved contracts

The exact inverse check restores the complete executed component with a single line replacement. Mounted lifetime, never-opened laziness, settle/static behavior, the actual content closure, natural-height measurement, zero-height clipping, host environment, hit testing, outer and inner hiding guards, animation progress, curves and durations are unchanged. There is no additional host, duplicate accessibility content, conditional visual subtree, forced unmount, timer, fallback renderer or test exception.

The original three call sites continue to instantiate the same component and keep their content/state/actions. The earlier retained-lifetime audit remains applicable: already-mounted arbitrary host child tasks follow the retained row until settle/removal; this candidate does not change that lifetime. It does not claim to prove behavior for every accessibility technology.

The22 protected fixture/test/runner/helper/control inputs are byte-identical to executed d8 and central4cfa. Central4cfa's selected workflow job and top-level prefix are byte-identical to executed d8, including the35-minute job envelope. This older isolated authoring branch still has the earlier25-minute workflow; it is NOT a proposed dispatch branch. Only this one-line component patch and these small evidence files should be integrated onto the reviewed current central source. No workflow blob is changed here. Linux Swift parser PASS is syntax evidence only.

## Proposed affected scope

After root review, freeze the exact current central integration plus this patch and run only the existing original B selector with unchanged35-minute job and600/720-second native allowances, one finite watcher and one capacity-admitted collector. It must satisfy the unchanged collapsed absence check before reaching the exact65/22ms burst and intermediate-height predicate. No synthetic or alternate test is proposed.

A plus changed-source C remain on hold for the qualified B outcome; D is not replayed. This preparation does not trigger CI or mark any Motion acceptance as passed.
