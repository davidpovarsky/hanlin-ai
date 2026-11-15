# Chat Motion implementation and acceptance

Original task: [CHATUX-MOTION1220546846740594](https://app.asana.com/0/0/1220546846740594).
SOLO developer chat01a1df7e-8483-7bd0-982d-1da876a89da3; isolated branch
`codex/hanlin-a2ui-wave1-20261115`. No main merge or distribution.

## Reference and source audit

[Fatbobman's article](https://fatbobman.com/en/posts/taming-row-height-and-spacing-jumps/),
sections4–5, and its linked
[AnimatedPresence Gist](https://gist.github.com/fatbobman/02a6ffffd58f0997b9f9155b89fea490)
were inspected. Neither displayed an explicit license. No Gist implementation is copied.
The new implementation independently uses a native animatable Layout: measure with a natural
height proposal, report a fraction of height plus spacing, place natural-size content and clip.
The existing LazyVStack remains the scroll owner. No replica of the article's general-purpose
stack is needed for a single trailing detail block.

Live Composer worktree status of ChatView, ChatViewComponents, SettingsView,
SettingsViewComponents and ChatPresentation paths was clean before edits. Existing Thinking
rounds, tool identities/input/output, result renderers, selection and scroll controller remain
authoritative. MorphView/ActiveChips, SDK/Host/engine/store/root/PBX are outside this change.

## Component checkpoint

Three production files define five stable versioned Codable IDs, a single configuration
mapping, one AppStorage string with known legacy normalization/invalid fallback, Reduce
Motion override, one native Picker and an interruptible shared disclosure. Initial mounted
content settles without replaying entry; opening mounts at zero before animation. Closing
keeps content until native animation completion. A revision guard ignores stale completions.
Streaming data is not an animation trigger. Default text scale stays1; only the explicit
gentle-squeeze preset permits0.985. Preset changes do not replace view identity or expansion.

Portable Swift checks executed on Windows: stable identity/Codable, migration/corrupt IDs,
ReduceMotion equivalence to static configuration, bounded tuning and Defaults serialization.
These do not validate SwiftUI, actual AppStorage/relaunch, geometry or runtime smoothness.
Six affected workflow-reading cache controls passed after adding the manual component route.
Unchanged cache/staging/performance controls retain their prior evidence; no broad rerun.

The initial three-source checkpoint compiled natively in
[43767448211](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43767448211),
source2b79df3f68c6aa5a47f6a0cf19d81cba8790b343, job41s. Simulator/device modules
were emitted for iOS26 deployment using SDK27.2/Xcode27.2; the model checks executed
on the Mac. Downloaded artifact14182084326 digest
`d885dbb9e7f028724442c07fb6bd51022840017180a11fadb4566b7f0be2afa6` was authenticated,
including source input hashes against that immutable Git commit. Receipt:
`evidence/component-43767448211.json`. This predates the added native DisclosureGroup
style and callsite integration; those changes are not covered by that historical compile.
The focused manual
`target_validation_group=chat_motion_component` route compiles the exact three production
files as a module for simulator/device SDKs with iOS26 deployment, plus runs model checks.
It records source/input hashes, actual toolchain/SDK and phase/exit status. It does not build
the full app or claim UI acceptance. Automatic workflow triggers are unchanged.

## Remaining acceptance — NOT_RUN

Chat/settings/count/status/shimmer/result callsites are now integrated. Original Thinking
and tool data/hierarchy remain; tool expansion bindings are held by stable activity ID in
the bubble so closing/reopening Thinking preserves individual tool choices. The original
ToggleButton uses the shared disclosure only for Thinking/resources; other legacy sections
retain their existing ownership/behavior. Counts no longer replace Text identity for every
new number. LoadingGradientText keeps its original blue gradient and uses central active
configuration; fixed24pt height was removed for DynamicType. Rich-card transitions use the
central bundle without changing final answer/action-bar transitions. No scroll code changed.
Eight new localized labels include Hebrew/Arabic/English/Chinese.

Native XCUITest is required for20 cycles per preset, rapid
reversal/switching, actual persistence/relaunch, ReduceMotion, multilingual long/short
Markdown/code, parallel/repeated tools/errors/cancel/no output, token/count streaming,
completion shimmer stop and paused-user scroll behavior. Actual iPadOS26/27 landscape,
portrait/compact, DynamicType, screenshots/video and timing evidence remain required.
Component-only passes cannot substitute for original-app regression/acceptance. Physical
iPad acceptance remains pending its owner. Full-app Runtime/Metadata integration remains
an external graph obligation; no passing component test proves that graph.

The prepared manual `chat_motion_ui` route materializes exact production component files,
the original LoadingGradientText/ToggleButton snippets (only outer private access lifted),
original blue asset and string catalog in a disposable iPad host. It builds once, then runs
three exact XCUITest methods. Geometry completion comes from native onGeometryChange,
not sleeps or AX disappearance during an incomplete close. Each preset must complete20
open/close cycles. First120s video, real height/time samples, screenshots and finalized raw
xcresult are retained. Recording uses a bounded host timer only; it never drives UI actions.
The fixture's long text includes Markdown syntax as literal text and native monospace output;
it does not exercise the original Markdown renderer, real AgentRun/parallel results or actual
ChatAutoFollowController behavior. Those original-app obligations remain NOT_RUN.
Current Xcode27 runner inventory has iOS27.0/27.1/27.2 only; iPad26 runtime acceptance is NOT_RUN.

First UI attempt43768841286 at3b16b802 was INFRA_ERROR before compilation/test preparation:
the fresh runner lacked XcodeGen (exit127, job16s), zero XCTest methods executed. The existing
repository convention of installing XcodeGen only when absent was added to this proof's
preflight. No production renderer/disclosure change was inferred from this infrastructure failure.

Second UI attempt43769077102 at0d5ff3fd reached build preparation but FAILED in the disposable
host's asset-catalog step: XcodeGen defaulted to an AppIcon set that this color-only fixture
does not contain (exit65, job47s). Zero UI methods executed. The fixture now explicitly leaves
its app-icon build setting empty; the product asset catalog is unchanged. Rapid reversal uses
one native three-tap gesture, avoiding serial tap calls that may wait for animation idle.
Both shimmer paths explicitly stop their TimelineView when scenePhase is inactive.

Third attempt43769467020 atbeca83e6 remained BUILD_FAILED, zero UI cases (job45s):
the project-level empty icon setting was overridden by XcodeGen's target preset. Its
[original SettingsBuilder](https://github.com/yonaskolb/XcodeGen/blob/master/Sources/XcodeGenKit/SettingsBuilder.swift)
was inspected. The override is now on the disposable app target itself; generated target
configurations are checked with native plutil before building, and generated PBX evidence
is archived. No product PBX or asset file was edited.

Fourth attempt43769856352 at4bf4d0e6 passed the generated target-setting check, then
BUILD_FAILED in fixture compilation: accessibilityReduceMotion is read-only in this SDK,
so it cannot be assigned with an environment modifier. Zero UI methods executed (job47s).
The artificial fixture override was removed. The XCUITest now changes the simulator's actual
Settings → Accessibility → Motion → Reduce Motion switch and restores the original value in
tearDown, following [Apple's documented path](https://support.apple.com/en-us/111781).
Both proof scripts now generate the repository's standard measured-phase performance report
on exit. Earlier artifacts retain their original missing-report limitation; no pass was
rerun solely to add accounting, and estimated savings are not treated as measurements.
