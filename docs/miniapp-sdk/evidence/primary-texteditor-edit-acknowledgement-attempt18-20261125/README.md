# TextEditor edit acknowledgement — attempt18 evidence

## Actual failure and correction boundary

The original MiniApps run on f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51 / SDK18 finalized with 22 passes, 3 failures and no skips. The original AI27 selection did not execute in that failed paired attempt. The stored paired state remains FAILED_OR_INCOMPLETE; a later separately authorized diagnostic is a different execution. The original runtime warnings remain in the unmodified summary.

Two of the three failures concern the authored Hanlin TextEditor adapter. The GeneratedModifiers test mounted the exact affinity editor but read an empty value instead of its unchanged default, Affinity example: hello مرحبا. The finalized ManualInput screenshot and accessibility tree show native text ala and the React-derived label EDITOR_VALUE:ala after the unchanged test typed alpha. This establishes that change events were delivered. It corrects the earlier incomplete possibility of missing callbacks: p and h were lost while native and controlled React state exchanged updates.

The original live captures and the first lifecycle analysis are unchanged in the preceding evidence commit abdb0eed018a83272a8e6a65c83add6d3e364433. This record adds the finalized screenshots and trees, rather than rewriting those observations.

## Exact source changes

The first reviewed production commit 38785cff47b019f15a6304484b5a979406978a14 mounts a real SwiftUI content view, supports the actual late delivery of initial props, and emits callbacks only from user edits. It applies a supplied controlled value ahead of a one-time default and preserves explicit empty defaults and subsequent uncontrolled edits. The previously retained original Expo source establishes that Props is constructed before updateRawProps delivers the React fields. No general claim that SwiftUI State is uninstalled in all Expo views is made.

The second reviewed production commit e16d37de564f13a86044c9e73bee1debce920820 adds an explicit edit acknowledgement to the private JS/native wire. Native edits carry an incrementing event count. The JS wrapper invokes the existing public callback first and then acknowledges that event. Controlled values can replace native text only after the wrapper has acknowledged the current native edit. Acknowledgement-only changes are observed so a parent that rejects or normalizes input still synchronizes even if the controlled string itself does not change. Programmatic Reset retains its normal path. Older compiled packages that omit the nullable native acknowledgement field retain their earlier behavior.

The public value/defaultValue/onValueChange interface, original fixtures, original two UI selectors and all their assertions remain unchanged. No RN or Expo vendor implementation was modified. Full source before/after hashes and Git modes, including the earlier lifecycle step, are in source-bindings.json. The two-path follow-up patch is in source-change.patch.

## Original implementation reference

The retained react-native 0.88.1 sources provide the original acknowledgement design: TextInput.js invokes public change handlers before updating mostRecentEventCount; RCTTextInputComponentView.mm rejects stale programmatic updates and increments the counter for native edits. The complete original files and license are retained under raw/original-react-native. The original package metadata, license and JS source were compared to their exact existing SDK18 ZIP members where present. The native Objective-C++ source is the retained original npm source; it is not newly retrieved from the Mac or a remote repository. Original-sources.json records that boundary.

Hanlin's SwiftUI TextEditor is an authored adapter using the same explicit ordering principle. It is not claimed to be RN TextInput copied verbatim.

## Verification still required

The parent reviewed both production diffs. No new TypeScript/native test or compiler was run by this evidence lane. Normal strict TypeScript/SDK preparation, affected native consumer compilation, and the two unchanged original affected UI cases must establish the corrected behavior. In particular the ManualInput assertion remains EDITOR_VALUE:alpha; the bilingual default assertion is unchanged.

The second correction changes Packages/HanlinExpoUI/src/manual-components.tsx, which is inside the existing stage-sdk recursive input root. A fresh actual SDK and rebuilt Expo fixtures are therefore required; SDK18 remains historical and must not be relabeled as the corrected package. The immutable baseline 22/3/0 result and any later diagnostic or final execution must remain distinct.

## Retained evidence

Only selected finalized original evidence is copied here: the frozen packet index, paired state, native summary, original attachment mapping, two accessibility trees and their two screenshots. The entire 248-member packet stays at its original transfer location. Selected members were independently checked against that packet's exact byte counts and SHA-256 records. Both selected screenshots were visually inspected in the prior uninterrupted analysis; the current copy preserves those exact bytes. This record does not claim a fresh reread of every large packet member.

The standalone receipt lists every stored member. It is evidence-only and does not change application source, selectors, SDK generation or old receipts.
