# Build 145001 regression repair: original Morph and V17

## Scope and provenance

The owner's physical iPad review of TestFlight 0.7.3 (145001) failed. The supplied screenshots show a persistent Thinking label after completed answers, capability cards changed into pale capsules, and a tool panel separated from the launcher by an oversized input shell. Two new crash reports accompany that review.

This repair starts from the exact source shipped in 145001:

- Parent commit: `4391dc17ca27b3233005f88c3d7f1fdb875ca4b5`.
- Branch: `codex/hanlin-original-ui-repair-20261121`.
- Isolated worktree: `C:\Users\DAVID\Code\hanlin-original-ui-repair-20261121`.
- The older dirty `hanlin-ai` user checkout and the previous release worktree are preserved.

Both canonical references were read in full and their original Windows bytes were authenticated:

| Reference | Size / lines | SHA-256 |
| --- | --- | --- |
| `Hanlin_Composer_MorphView_Bubble_Experiment.swift` | 52,206 bytes / 1,269 lines | `51bb10cdf71ee1c10cac8108f602eee4b34e78967de23dc437985aa89db9bbbb` |
| `Hanlin_Live_Conversation_v17_Integration_Annotated.swift` | 111,252 bytes / 2,391 lines | `f984930f659c34b791d610b3716b7cfb3d9545040b2c4d567b181a4ec46cc14e` |

The originals are immutable references. Their demo application entry points, mock services, synthetic timers, invented progress, and parallel storage are not production integration code.

## Findings and repairs

### Original Morph composition

The original quick bar is outside the entire glass shell. Production had placed the model/action controls and a resize handle inside the editor. That enlarged an empty input to approximately 130–180 points. With the original bottom-aligned 52-point launcher, the panel-to-launcher gap becomes `13 + max(0, inputHeight - 52)`, exceeding the glass container's 32-point merge distance.

The repair restores:

- A separate quick bar containing the actual model, tool, microphone and full-editor controls.
- One persistent native editor subtree, with a 52-point empty shell and the original one-empty-line / two-to-six-draft-line behavior.
- The original 52-point launcher, 13-point panel spacing, 10-point launcher/input spacing, 27-point input radius, 29-point panel radius, 16-point panel inset, and one namespace with the three original glass identities.
- The original tagged-page measurement and animation of the outer viewport height. Child content retains its natural size.
- Original blue capability cards: `#3A7CB4`, white text, continuous 17-point rounded rectangles, tinted interactive glass, and azure outline. The native bordered-button mutation that created capsules is removed.
- The original compact home hierarchy and all nine live destinations, including Mini Apps and model parameters. Mini Apps opens the existing `NativeAppsHubView` through a native sheet; no demo catalog is copied.
- Real attachments and the existing native searches remain connected. Shared Items remains a compact production action.
- Empty attachment scroll views are no longer mounted at zero height. The page scroll view only exists for a positive finite viewport; its animated height is clamped against the current available budget.

The shared palette and geometry are defined once in `HanlinMorphStyle`, beside the existing typography and control catalog in `HanlinDesignCatalog.swift`.

The reference itself bottom-aligns the launcher beside a growing multiline draft. This repair restores that composition; it does not introduce a second bridge shape to fabricate a different connection for arbitrarily tall drafts.

### Activity lifetime and V17 presentation

The persistent Thinking label had a direct code cause: the root activity header always used `String(localized: "Thinking")`. Completion only stopped its shimmer, leaving the live-tense label visible. A separate operational footer could also admit archived status text.

The repair adds a presentation phase policy:

| Current state | Header | Shimmer |
| --- | --- | --- |
| Active run | Working through your request | Active |
| Active run awaiting approval | Waiting for your confirmation | Off |
| Completed, failed, cancelled or reopened history | Activity history | Off |

The footer is only eligible for the current active message when there is no activity header. Historical running/pending tool labels are resolved to the actual operation name; a retained in-progress or consent summary is no longer used as a completed result title.

V17 adaptations reuse the real run, round and call identities:

- Shared hierarchy header, adjacent fading disclosure arrow, nested guides and native disclosure semantics.
- Existing `HanlinAnimatedDisclosure` remains the natural-height reveal mechanism.
- One canonical letter-mask shimmer for activity, reasoning and tool titles: the reference's blue/white gradient, beam width `max(32, width * 0.54)`, default period 1.95 seconds, and 24 Hz decorative timeline.
- Preserved motion preferences, Reduce Motion, VoiceOver, scene activity and collapsed-branch visibility.
- Active web/source-search and code/command surfaces use the original rounded live-card treatment. Completion freezes the current animation position and fades into the compact result, without advancing to the end of a fabricated progress path.
- Technical details remain explicitly expandable. The final row does not repeat a Completed/Allowed once receipt as a second result.
- Inline approval title, the full supplied redacted request scope and actions share one surface. A bounded native review region keeps the actual Host request visible before a decision; extra technical detail remains manually expandable. An explicit empty review cannot be allowed, while a legitimate zero-argument JSON object remains valid. The existing request identity, one-shot submission guard and actual execution gate are retained.
- Observed source icons/counts remain real. Their reference widths are ideal/max widths, allowing compression inside narrow iPad activity hierarchies.

#### Progress data boundary

The platform contract has a validated optional `HanlinToolProgressEvent.fractionCompleted`, but current production does not populate it. The app's progress producer supplies message text; runtime snapshots contain state and stdout/stderr byte counts, without a work total. The chat presentation does not receive a numeric file-progress value.

Therefore a file operation retains the truthful active title treatment. The reference's mock file percentages, flight route and fare animation cannot be presented as real measured progress without matching Host metadata. This source repair makes no numeric-progress or flight-data claim.

### New scroll-attachment crashes

The new reports are:

- `EF9937EB-F636-4304-B5C2-12C8A461DAC2`, 21 November 2026, 21:28:05 +0200.
- `470A5427-ACBB-4391-9505-82C4BE140E27`, 21 November 2026, 21:29:33 +0200.

Both are Build 145001 on iPad15,3 / iPadOS 27.2.1 (24B156), main-thread SIGABRT. The shared exception path is:

`CA::Layer::set_bounds → CALayer.setBounds → UIScrollView.setBounds → HostingScrollView.bounds.setter → setContentOffset → updateContext → flushPendingContext → didMoveToWindow`

These are distinct from the earlier sensory-feedback SIGBUS report. Neither new report includes the exception reason or an app frame identifying the offending scroll view. The exact sole cause is not proven by those stacks.

Concrete source defects corrected:

- Removed the mutable message-count-dependent `defaultScrollAnchor`, which competed with explicit auto-follow during native attachment and size changes.
- The measured auto-follow controller is the single owner of programmatic transcript positioning.
- Saved-source reveal/correction tasks are retained, cancelled and bound to their current request, conversation, target and viewport generation.
- Execution re-reads native window attachment and finite positive geometry before using a retained scroll proxy.
- User scrolling, selection, disappearance, changed/deleted targets, conversation change and history clearing cancel stale work.
- Finite inputs and their arithmetic results are checked; valid offset ranges and near-bottom calculations reject overflow, NaN and infinity.
- A weak, non-observable native viewport handle supplies one deferred readiness callback after valid attachment/layout. It does not publish observable state during UIKit layout, poll for readiness, or retain the scroll view.
- Teardown cancels readiness, restores the existing touch setting and clears the bridge callback.

These changes remove unsafe paths. Physical crash elimination remains an iPad acceptance result.

## Source map

| Reference area | Production owner |
| --- | --- |
| Morph quick bar 387–426; shell/input 429–536 | `ChatViewBottom.swift`, `HanlinMorphComposer.swift` |
| Morph measured pages and height adoption | `HanlinMorphGeometry`, `HanlinMorphMeasuredPages` |
| Morph home/cards 802–950 and original page destinations | `HanlinComposerPopupView.swift`, `HanlinMorphStyle` |
| V17 hierarchy 1333–1405; arrow 2098–2118 | `HanlinActivityHierarchy.swift`, real activity/round call sites |
| V17 approval 1410–1558 | `HanlinInlineToolApproval.swift` |
| V17 tool row 1564–1753; live surface 1843–2040 | `HanlinToolActivityHeader.swift`, `AgentActivityContentView` |
| V17 title shimmer 1755–1840 | `ChatShimmerEffect.swift`, default motion configuration |
| Transcript lifecycle and scroll safety | `ChatView.swift`, `ChatAutoFollowController.swift`, `ChatScrollViewHandle.swift` |

## Verification

Executed on Swift 6.3.3 / Windows:

| Check | Result | What it establishes |
| --- | --- | --- |
| Actual Morph geometry functions and eight regression methods | 8 passed | Budget/height policy, source launcher gap, invalid viewport rejection |
| Actual production `ChatAutoFollowController` and unchanged actual test source, disabled diagnostics stub only | 12 passed | Coalescing, interaction/cancellation, stale timer, short content, invalid/overflow geometry and fresh-layout requirements |
| Actual header-phase and motion configuration source | 19 checks passed | Live/waiting/history eligibility and motion timing policy |
| Localization comparison against parent commit | 1,049 original entries unchanged; 21 new keys / 63 translations validated | Exact English, Hebrew and Simplified Chinese values, UTF-8 preservation and valid JSON |

Swift syntax parsing is a source check, not Apple SDK typechecking. The Apple Release archive is the subsequent compilation/signing check.

Added/revised test source, not executed on Apple in this repair:

- Five UIKit viewport lifetime/readiness cases in `ChatScrollViewHandleTests.swift`.
- Header/title regression cases in `AgentActivityHeaderPhaseTests.swift`.
- Existing Morph/conversation UI assertions updated from the removed custom resize handle to the native expanded editor and automatic line limits. The existing simulator fixture remains simulator/test gated.

The prior draft-persistence, stream coalescing, exact UTF-8 run cache, native text-editor, native-search, central typography and feedback changes are retained. No new device latency/FPS measurement is claimed here.

## Release contract

The owner explicitly authorized implementation and TestFlight publication and requested no simulator tests in the upload run.

Use the already-proven main workflow route:

- Workflow `310046367`, `build-ios26-unsigned-ipa.yml`.
- `testflight_upload=true`.
- `target_validation_group=testflight_device_upload` (the reusable upload receives the simulator-skip setting through this group).
- `runtime_bundle_artifact_run_id=42926628418`.
- `runtime_bundle_only=false`.
- `runtime_publish_release=false`.
- `testflight_audience_source_build=143801`.

The native runtime is reused; the app archive is rebuilt from this repair branch. The runtime lock, signing, privacy, entitlement and Apple readiness checks remain in place.

Native bundle dependency identity:
`2ac91db28c0bee53ae53afae8e30a934e7a23d5c706cc321f7c91cbc68523194`.

The final release receipt must record the exact source SHA, workflow run, Apple build ID/number, `VALID` processing and `IN_BETA_TESTING` internal state. Upload success alone is not that receipt.

## Owner acceptance remains open

Record results on the installed new build, not on 145001 or a simulator build:

- Completed/reopened, failed and cancelled responses do not retain an active Thinking/searching label or shimmer.
- Live search/tool titles use the canonical shimmer and freeze/fade at the real completion event.
- Inline approval remains tied to the actual call and prevents execution until the real decision.
- Empty and multiline drafts, popup navigation, keyboard, portrait/landscape and narrow split view preserve the native editor and visible controls.
- The blue cards, quick bar, plus/input/panel relation and height transitions match the originals in the actual iPad environment.
- Long transcript entry/re-entry, source jumps, selection, finger scrolling and content shrink do not reproduce the supplied crash path.
- Hebrew/English, Dynamic Type, Reduce Motion and VoiceOver retain usable layout.

Tracking:

- Master: https://app.asana.com/0/1219603102275846/1220776535218599
- Morph: https://app.asana.com/0/1219603102275846/1220539644804804
- V17: https://app.asana.com/0/1219603102275846/1220588718902198
- Physical/UI acceptance: https://app.asana.com/0/1219603102275846/1220083352349478

These acceptance tasks remain open. The release receipt and any subsequent physical findings belong in their activity records.

## First Apple archive and localization correction

The first repair attempt, [run 44952550947](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44952550947), used source `72bf6f2b29e64585fc1ec85762dbe0f120f772a1` and failed before upload in Xcode's GenerateStringSymbols phase. Three newly added keys produced the same generated Swift symbols as existing keys: `Agent Capabilities` / `Agent capabilities`, `Local runtimes` / `Local Runtimes`, and `Mini Apps` / `MiniApps`.

The follow-up changes only the three new lookup identifiers to `hanlin.morph.agentCapabilitiesTitle`, `hanlin.morph.localRuntimesDescription`, and `hanlin.morph.miniAppsTitle`. Their English, Hebrew and Simplified Chinese values are unchanged, and all 1,049 pre-existing catalogue entries remain identical. A focused normalized-key collision check passes for all 21 additions. This check does not substitute for Xcode's actual string symbol generation; a fresh signed archive is required. This failed attempt did not produce an available TestFlight build.

## Verified TestFlight distribution (22 November 2026)

The retry [run 44955994342](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44955994342) completed successfully. Apple confirmed readiness at 01:19 on 22 November 2026 (Asia/Hebron; receipt timestamp `2026-11-21T23:19:10Z`).

| Receipt field | Verified value |
| --- | --- |
| Version / build | `0.7.3 (145201)` |
| Shipped implementation source | `927001ac4ac2f3f3cf837df50ec3bb20a0648b48` |
| App ID | `6811910017` |
| Apple build ID | `1e3cd763-54a8-447a-b6e1-2795c1c8f59f` |
| Processing state | `VALID` |
| Internal testing state | `IN_BETA_TESTING` |
| Existing audience source | Build `143801` |
| Verified internal group | `14fdc6a7-062e-40f6-8f11-45cbd30c6ddb` |
| Native Runtime producer | `42926628418` |
| Simulator-test input | `skip_simulator_tests: true` |

The signed Apple archive, export, App Store Connect validation, upload and readiness verification all passed. The exact source SHA in the readiness receipt matches the successful workflow's head SHA. One existing internal group was reused and its assignment verified. External beta state is `READY_FOR_BETA_SUBMISSION`; this receipt proves availability to the existing internal audience.

The 39 executed production-logic checks remain the validation described above. No simulator or physical-iPad UI run was added. Physical parity, keyboard/streaming performance measurements and crash recurrence acceptance remain open in Asana. This receipt section was added after distribution; the shipped implementation source is the SHA in the table, and this documentation update does not change app code.
