# Retained disclosure: owned presentation containment

## Actual failure and scope

The original Motion B diagnostic on `cff1e85b4a8996d4ba76db2816314fe0b4347eeb` executed one case and failed in 12.823349 seconds, native exit 65. The original runner removed its owned simulator. This was diagnostic evidence, not native acceptance.

The 68 retained stream/fallback matches describe 34 distinct events, keyed by PID, mach timestamp, kind and complete fields: 18 STATE, 11 HOST and 5 ROOT events. They all belong to AUT PID 40857. The failure-only native capture completed with 36 views, 73 layers and 66 public accessibility objects, no truncation, and its acknowledgement completed.

For the same content type, host token and UIView 0x105da1200:

| Event | Epoch seconds |
| --- | ---: |
| Collapse requested, generation 3 | 1795609541.676756 |
| Matching `.removed` completion delivered | 1795609542.009278 |
| Completion set physical hidden state | 1795609542.009969 |
| Owned UIView setter read back `isHidden=true` | 1795609542.0114388 |
| Fresh failure AX capture began | 1795609543.029818 |
| Same native hosting view captured | 1795609543.372637 |

The native capture still had `isHidden=true`, `accessibilityElementsHidden=true`, hidden model and presentation layers, and no layer animations. Its ordinary accessibility child array was empty, but its automation child array retained a SwiftUI node. The public automation edges reached the same summary label and frame seen in the fresh XCTest snapshot. That snapshot contained one summary, `hittable=false`.

These records establish that the completion and visibility update ran, and that the same view was still hidden at the later native sample. They do not support a missed update or visibility overwrite as the cause. The samples are not continuous observation, and they do not establish that every hidden UIView behaves this way. The exact raw artifact hashes and source bindings are in `causal-proof.json`; the failed baseline remains failed.

## Candidate

The clean candidate starts from `b7856bb23b2f415f78b752fe2222ea654f3aa8b2`, without the diagnostic logging or failure observer. It changes only the existing private UIKit scope in `HanlinAnimatedDisclosure.swift`.

The representable now owns a plain container controller, which retains one `UIHostingController<Root>`. When the already-existing collapse completion closes the physical gate, the container removes that child controller/view with the documented containment sequence. Reopening attaches the same retained controller and view before the original opening animation. No new hosting controller or replacement Root type is created by either operation.

The original state, generation/reversal guard, completion criterion, animation curves, geometry, semantic hide, environment forwarding and update transaction are unchanged. Natural-size measurement still calls the retained hosting controller. The plain container forwards the hosted view's intrinsic-size fallback for unspecified proposals. The original fixture, actions, assertions, deadlines and runner remain byte-identical.

The implementation uses public containment APIs, with no timers, private view matching, test-specific identifiers or automation-property overrides. [Apple's container documentation](https://developer.apple.com/documentation/uikit/creating-a-custom-container-view-controller.md) specifies the ordered add/remove calls and explicitly permits retaining a removed child controller. [Apple's `isHidden` documentation](https://developer.apple.com/documentation/uikit/uiview/ishidden.md) describes hidden views remaining in their superview's subview list; it does not promise removal from the automation graph.

## Validation status

Source checks verify unchanged outer animation/completion code, Root value/environment code, disclosure style/layout, original App, original Motion tests, runner and preset configuration. `git diff --check` passes. These are source checks, not an Apple compiler or runtime result.

**Candidate native compilation and acceptance are NOT_RUN.** Root owns the actual original B run and then the original A/C gates. Those must establish disappearance from the closed automation hierarchy, successful reopening, retained content state, natural sizing and the expected lifecycle/animation behavior. Retaining the controller reference alone is not a runtime proof of every SwiftUI state or appearance effect.
