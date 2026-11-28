# MiniApps editor equality guards

## Change and scope

The existing `MiniAppsCodeTextView` assigns editability and font during every `updateUIView` call. Its delegate also writes the text, selection and caret bindings without checking whether their values changed. The text binding calls `project.edited()`, which increments the project revision and updates recovery state.

This change compares those five values before assignment. A real text change still reaches the same binding setter and `project.edited()`; selection and caret observation still follow every text callback. The incoming text comparison, incoming selection bounds check, caret geometry expression and all surrounding editor code remain unchanged.

No task, timer, asynchronous deferral, delegate suppression, API or test is added. All original UI selectors, assertions and deadlines remain unchanged. The changed app source is outside the measured 396-file SDK input set.

## Evidence and limits

Four retained samples from the original Gallery run bind to the Departure and Table app processes. They show repeated editor font-update frames and separate scroll-to-caret assignment paths over multiple observations. No sampled caret-setter ancestor chain contains `updateUIView`; the samples therefore do not establish a synchronous callback cycle.

The original paired test log names four Studio cases when reporting state-during-view-update warnings, including Departure and Table. It does not supply a warning backtrace or process identifier. These warnings support further native verification but do not establish this change as the cause or cure of the observed hangs.

The source rationale is narrower: assigning an unchanged value is unnecessary for this editor's value bindings. Apple's `textViewDidChange` contract describes user-initiated changes rather than programmatic changes; this patch does not assume a programmatic font assignment invokes `project.edited()`.

## Qualification

The five substitutions can be reversed to recover the complete original source byte for byte. Code outside `MiniAppsCodeTextView` is unchanged. The original caret geometry and existing incoming text/selection checks are retained. Source review and `git diff --check` qualify only this bounded implementation.

Swift compilation, native behavior and the original Gallery/editor routes remain required. There is no native performance or acceptance claim in this source packet. Existing successful platform-package tests do not execute this app editor and are not used to qualify it.

## Source authorities

- Base: `53329e1a9dde33432d886ec5ffbee7c3d44d2014`.
- File: `HanlinMiniAppsApp/MiniAppsDeveloperStudio.swift`.
- Original SHA-256: `1471af7b39899452fd3ab797bf24cd9d4e1c2273807e438795564ebe259608d7`.
- Candidate SHA-256: `28058e1a2b8189a16e6a517d20e64db7ff76c9aebc6ddc120cde16963baa8c4c`.
- Model source SHA-256: `849851553729e4bbcedd623441a5e75c5320d76bdf0a0f48130c9bfe6ff20df1`.
- [Apple: updating a represented UIKit view](https://developer.apple.com/documentation/swiftui/uiviewrepresentable/updateuiview(_:context:)).
- [Apple: textViewDidChange](https://developer.apple.com/documentation/uikit/uitextviewdelegate/textviewdidchange(_:)).

The qualification file records exact source, patch and evidence bindings. Raw native evidence is retained separately; this compact proof does not reproduce source archives, full process samples or unrelated project material.
