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

Native component compilation is NOT_RUN at this checkpoint. The focused manual
`target_validation_group=chat_motion_component` route compiles the exact three production
files as a module for simulator/device SDKs with iOS26 deployment, plus runs model checks.
It records source/input hashes, actual toolchain/SDK and phase/exit status. It does not build
the full app or claim UI acceptance. Automatic workflow triggers are unchanged.

## Remaining acceptance — NOT_RUN

Chat/settings/count/status/shimmer/result integration awaits component compile before
changing original callsites. Native XCUITest is required for20 cycles per preset, rapid
reversal/switching, actual persistence/relaunch, ReduceMotion, multilingual long/short
Markdown/code, parallel/repeated tools/errors/cancel/no output, token/count streaming,
completion shimmer stop and paused-user scroll behavior. Actual iPadOS26/27 landscape,
portrait/compact, DynamicType, screenshots/video and timing evidence remain required.
Component-only passes cannot substitute for original-app regression/acceptance. Physical
iPad acceptance remains pending its owner. Full-app Runtime/Metadata integration remains
an external graph obligation; no passing component test proves that graph.
