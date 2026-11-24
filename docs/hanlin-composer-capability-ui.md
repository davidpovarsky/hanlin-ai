# Composer capability UI

The shared `HanlinChatUI` module owns the draft, typed attachment picker, configuration controls, native-editor query hooks and attachment summaries. It depends on the existing `HanlinPlatformContracts` module; an embedding application does not need the Hanlin application executable.

## Draft and send boundary

Use one `HanlinComposerDraft` for one conversation's composer. Its `capabilityAttachments` are separate from the host's enabled-tool preferences. `attach(_:)` returns the attached UUID and preserves the existing configuration when the same reference/action is selected again.

Copy `draft.capabilitySnapshot` into the outgoing request when sending. This is a value snapshot. Subsequent edits, removing a chip or clearing the draft do not alter the submitted message. Resolve the snapshot against the current host catalog and validate the revision, action, configuration and invocation policy before executing any tool.

Selecting a row, changing a control and moving a map pin only edit this draft. No picker invokes an app entrypoint or tool handler.

## Selection in a host

`HanlinCapabilityPicker(capabilities:attachments:onSelect:)` displays host descriptors and declared actions. Supply the same descriptor list to the pickers and native-editor suggestions so all insertion routes produce the same reference and configuration defaults.

The Hanlin app supplies this list to `ChatViewBottom` together with `capabilityDraft`. Its tool, skill, MCP and MiniApp pages expose explicit attachment selection separately from their existing availability controls. The MiniApp composer page includes only assistant capabilities supplied by the host catalog. Ordinary foreground app launch remains in the app library.

`HanlinCapabilityAttachmentChips` accepts optional `onEdit` and `onRemove` closures. `HanlinCapabilityAttachmentSummary` is the read-only variant for submitted messages.

## Configuration inside the existing bubble

`HanlinCapabilityConfigurationView` takes a descriptor and a binding to one attachment. It is content only: the host provides scrolling, navigation and the surrounding composer bubble.

The declaration can contain multiple panels. The view renders a native panel menu, action menu, text and number fields, toggles, single and multiple choices, a hierarchical catalog and a MapKit location selector. A location value is:

```json
{ "latitude": 31.778, "longitude": 35.235, "radiusMeters": 1500 }
```

The map supports tapping a pin, selecting its visible center and editing coordinates with native text controls. It does not request the current location or run a places search. The field's minimum and maximum apply to `radiusMeters`. Unknown/invalid values remain subject to the configuration schema; invalid intermediate number text cannot silently send a previously valid value.

For a host-specific native component, use the generic initializer:

```swift
HanlinCapabilityConfigurationView(
    capability: descriptor,
    attachment: attachmentBinding,
    supportsCustomPanel: { $0 == "my.catalog" },
    onDone: closeConfiguration
) { panelID, configuration in
    MyCatalogPicker(configuration: configuration)
}
```

The host resolves `customViewID` to a component it actually provides. The default initializer shows an unavailable message and disables Done for a custom panel it cannot render. It never launches an ordinary MiniApp as a substitute. The host validates custom component output against the declared action/input contract before dispatch.

## @ and / queries

`HanlinComposerCapabilityQuery.parse(text:selection:hasMarkedText:)` uses the UTF-16 insertion point rather than assuming the caret is at the end. It ignores marked text, nonempty selections, emails and URLs, and tracks the whole token containing the caret. Before replacing a token, `replacingToken(in:with:)` checks that the original token is still present.

`NativeMultilineTextEditor` exposes `onCapabilityQueryChange` and a one-shot `SelectionRequest`. The request is accepted only for matching text and draft ownership, so choosing a suggestion in the middle of RTL/emoji text preserves surrounding content and places the caret after the replacement. Existing AI-model mentions remain available alongside capability suggestions.

## Validation evidence

Focused tests are in `HanlinComposerCapabilityTests.swift`:

- UTF-16 / RTL / emoji token replacement and caret positioning;
- slash query replacement, stale query and marked-text rejection;
- email/URL rejection and preserved model-mention representation;
- independent drafts, immutable sent snapshots and repeated selection.

The draft tests require UIKit and therefore an iOS test destination. Native compilation, simulator interaction and application integration must be recorded separately; source tests and documentation are not build receipts.
