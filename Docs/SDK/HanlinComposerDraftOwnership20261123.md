# Original native Composer draft ownership — 23 November 2026

## Observed real-host defect

Lorvex native UI run [45133684085](https://github.com/davidpovarsky/lorvex/actions/runs/45133684085) compiled and launched consumer `e00fc6059d5d8108311c8e263462fe4400335a1f` against canonical SDK `d49a4fd4115b8335105d2991bf74ab4d7f6aad2d` using Xcode 27.2 / iOS 27.2. Its original `HanlinSDKIntegrationTests/testOriginalComposerInsideLorvex` reached the original native editor, multiline input, enabled Send control, Morph panel and real Lorvex tool catalog. The existing draft assertion at line 37 failed; reopen was not reached.

The original native screenshot taken immediately after typing, **before opening Morph**, reads `lan this week` followed by `Keep time for reading and rest.P`, with the insertion caret before the final P. The later tool-panel screenshot preserves that same ordering. This is observed typing/caret corruption, not proof of a panel-close data-loss defect. The run did not enable the existing sanitized edit trace, so the exact delegate/render interleaving is not established by this evidence.

| Retained evidence | Identity |
| --- | --- |
| GitHub diagnostic artifact | `14803208882`, 98,005,168 bytes |
| Artifact SHA-256 | `9e2579a945d86b0d9964d3a8583eef1c43ee3012747b083f6a68a1020a028eb8` |
| Original multiline screenshot | `53B1B018-1092-4C98-8CF2-8C4E4ED729B6.png` |
| Screenshot SHA-256 | `3830df391bb72bf07263532ad26d0e33bd2fc386719f7a4ba2267bbece973ab0` |
| Job log SHA-256 | `2039f55fc5f930c0cc3f724dc6fe0da6a3c1bffe3ae9adf2d221c2f901b1ba84` |

The Oracle consumer retains the artifact and extracted visual evidence under `apps/apple/dist/hanlin-local/ui-stable-toolchain-evidence/`.

## Confirmed ownership mismatch and canonical correction

The editor's existing `readCurrentTextState` contract requires a synchronous read of the **same live owner mutated by its Binding**. Lorvex supplied a closure over two captured SwiftUI Binding values (`text` and `revision`) passed through independently rendered views. That closure did not provide independent live authority, and the two separate writes did not preserve the original atomic text/revision snapshot update.

Original Hanlin already solves that boundary with its retained `@MainActor @Observable HanlinComposerDraft`. This change moves that exact implementation from `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinComposerSessionBridge.swift` into the public `HanlinChatUI` product at `Composer/HanlinComposerDraft.swift`. The app retains a compatibility typealias and consumes the same shared implementation. There is one concrete class declaration and no copied draft implementation in the consumer.

The only declaration changes are public access on the class, readable snapshot, text property and initializer. The original constructor, text getter/setter and snapshot logic are unchanged. Every write, including a same-value explicit clear, still atomically replaces the snapshot with the stable owner ID, a new revision UUID and the new text.

Original declaration and moved declaration after stripping only those four public-access tokens have the same SHA-256:

`3b0dbcc58683b32a9b9685a329652c3a945f07b61806fbd96080e373673b0190`

The declaration remains UIKit-only because its snapshot is `NativeMultilineTextEditor.TextState`. Lorvex's portable Agent module remains independent of UIKit. Its UI adapter retains the shared draft reference in the assistant view, passes that reference through workspace/composer, binds writes to `draft.text`, and reads `draft.snapshot` synchronously. Existing non-UIKit presentation fallbacks remain guarded.

## Host usage

```swift
import HanlinChatUI
import SwiftUI

@State private var draft = HanlinComposerDraft()

// In the original Composer input closure:
NativeMultilineTextEditor(
    text: Binding(get: { [draft] in draft.text },
                  set: { [draft] in draft.text = $0 }),
    textHeight: $measuredHeight,
    readCurrentTextState: { [draft] in draft.snapshot }
)
```

Retain one draft owner for each independent draft lifetime. Use the same reference for editor reads, writes and programmatic clears. The shared type does not create an agent, storage layer or conversation.

## Verification and exact remaining scope

- Source preservation compares the complete original declaration with the public-access-normalized moved declaration; the bodies are byte-identical.
- Existing app references and `@testable import AI_Hanlin` tests continue through the compatibility alias. The original native editor implementation, layout, keyboard handling, Morph component and acceptance assertions are untouched by this source move.
- Existing `NativeComposerLineSizingTests` already exercise retained render snapshots, live-owner clears, owner switches and exact character/selection preservation with this original draft implementation. Their previous results are evidence for those exact prior inputs, not a claim that this module move has passed an Apple compiler.
- The actual failed Lorvex UI scope must run once against the published unified SDK containing this change. Until that native run completes, this receipt records a source-level correction, not UI acceptance.
- The six Agent test results and device export from run `45119218473` remain retained at their original source identities; they are not rerun or relabeled as this modified UI's binary.
