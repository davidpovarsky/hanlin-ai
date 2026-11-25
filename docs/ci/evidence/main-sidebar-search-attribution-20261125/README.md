# Main Search navigation attribution

The retained original Search case reaches its row callback and constructs chat content, but UIKit reports that it cannot update a navigation stack while another transition or presentation is active. The warning occurs 278.212 ms after the authenticated row tap. The final accessibility hierarchy remains Home. This is distinct from Row's initially empty fixture store and Hebrew's editor ownership failure.

## Source scope

This additive DEBUG/HANLIN_TESTING diagnostic uses the existing editor's actual window and public controller relationships. It records controller identities and presentation/dismissal flags; native navigation top/visible/stack identities; and an existing transition coordinator's identity, timing flags, and from/to controller identities. It never loads a view, traverses private view ancestry, changes a delegate, or mutates navigation/focus.

Trace points are immediately before the row ends search, before the existing path assignment, at the existing path change, and at one weak, generation-bound yielded observation. The yield only schedules an observation; it is never a routing or readiness gate. Path fields are labeled as event snapshots.

Traversal is bounded to 32 unique controller nodes, depth 8, and 24 captures per owner. Short begin/node/edge/transition/end records retain limit and unavailable-root states; missing or truncated records must remain incomplete evidence. Original production statements, bootstrap, fixtures, test actions, assertions and timeouts are unchanged.

## Verification and remaining obligation

Insertion-only diff, equality after removal of diagnostic conditional sections, unchanged original input hashes, and independent source review passed. No build or native test was run. The exact next plan remains the five original UI selectors plus four previously omitted Swift Testing selectors, including parentheses in their method identifiers, recorded in qualification.json.

This observation is not a Search production correction. The actual controller/coordinator identities must determine any later supported serialization; a fixed delay or an unrelated animation completion does not establish UIKit readiness. The root agent owns native dispatch and the Mac source/cache.

## Public API basis

- [UIViewController.transitionCoordinator](https://developer.apple.com/documentation/uikit/uiviewcontroller/transitioncoordinator)
- [UIViewControllerTransitionCoordinator](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioncoordinator)
- [SwiftUI withAnimation completion](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:))
