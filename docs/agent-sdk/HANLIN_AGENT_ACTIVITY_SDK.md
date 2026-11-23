# Original Hanlin activity as independent SDK products

`HanlinAgentActivityCore` and `HanlinAgentActivityUI` expose the original activity implementation without importing the complete Hanlin application or a native runtime.

## Product boundaries

| Product | Canonical implementation | Dependencies |
| --- | --- | --- |
| `HanlinAgentActivityCore` | Original activity/run/transcript/evidence DTOs, composition, round ownership, visibility/title/detail policies, tool profiles, per-call projection, redaction, native-result DTOs and immutable activity snapshots | `HanlinPlatformContracts`, `HanlinPresentationKit`, `HanlinLocalization` |
| `HanlinAgentActivityUI` | Original activity hierarchy and detail disclosures, step row, approval presentation and callbacks | `HanlinAgentActivityCore`, `HanlinChatUI`, `HanlinPresentationKit`, `HanlinLocalization` |

These are optional products. `HanlinChatUI` does not depend on either of them. A host selecting only the existing Composer, bubble or other ChatUI primitives keeps its previous selected source closure.

## Use the original hierarchy

Import `HanlinAgentActivityCore` and `HanlinAgentActivityUI`. Construct a `HanlinAgentActivitySnapshot` from the host's original `AgentRun` value and render `HanlinAgentActivityView(snapshot:isExpanded:toolApproval:messageState:)` where the host wants the activity hierarchy. The surrounding host view owns placement and the expansion binding; standard SwiftUI modifiers and the existing Hanlin motion environment continue to apply.

```swift
HanlinAgentActivityView(
    snapshot: HanlinAgentActivitySnapshot(
        run: currentRun,
        reasoning: reasoning,
        reasoningTime: reasoningTime,
        legacyToolContent: legacyToolContent,
        isActive: isCurrentRunActive,
        hasAnswerText: hasStartedAssistantAnswer
    ),
    isExpanded: $isActivityExpanded,
    toolApproval: verifiedApprovalPresentation,
    messageState: messageOpenUIState
)
.equatable()
```

The snapshot removes assistant answer deltas and `finalAnswer` using the original invalidation filter. It leaves actual tool, source, reasoning and approval receipts intact. `AgentRun`, its original models and the original composition/projection APIs retain their existing names and Codable schema.

`messageState` is the existing `HanlinPresentationKit.MessageOpenUIStateStore`. Supplying it preserves the same activity disclosure ownership used by mixed rich content. When absent, the original local view state remains available. No second store or presentation model is synthesized by the view.

For pending approvals, construct the public `ChatToolApprovalPresentation` from the host's verified request identity, original review text and real answer continuation. Persisted `AgentToolApproval` receipts only describe the original request/outcome. The original UI delegates an answer to the supplied continuation and never creates permission from a receipt.

Hosts that want an individual original row can use `AgentActivityStepView(activity:isLast:onSelectActivity:)`. Hosts rendering their own activity layout can use the original Core composition and projection APIs without importing the SwiftUI activity target.

## Hanlin consumes the same implementation

`ChatBubbleView.AgentActivityContentView` now forwards its original inputs, binding and `hanlinRichMessageContext.state` to `HanlinAgentActivityView`. Its original name remains available for existing application and test call sites. The original hierarchy, shimmer ownership, approval row, lazy detail projection, source links, technical text, disclosure styles and accessibility identifiers are implemented in the SDK.

`ClassicChatAgentProjection` delegates its pure per-call projection to `AgentActivityToolProjection`. The application retains its SwiftData persistence adapter. Original NativeUI JSON trace logging and app-specific native route factories remain extensions in the application; the schema definitions themselves have one owner in Core.

## Verification and integration

The extraction receipt is `docs/agent-sdk/evidence/agent-activity-extraction-20261123.json`. It records 29 preservation checks, 55 parsed Swift files and the existing 202 production activity lifetime/motion assertions executed against the moved canonical policies. Public constructor additions and explicit state/module/isolation seams are the only changes to moved original source. No SwiftData model or resource catalog is moved in this extraction.

The verified Swift 6 equality failure is addressed by keeping the view value explicitly nonisolated while its body, initializer and UI helpers execute on MainActor. Original equality predicates are unchanged; no unsafe actor assumptions or unchecked Sendable conformance are introduced.

Actual Apple compilation and relevant original UI acceptance remain part of the parent-owned combined gate. Portable/source evidence does not claim native rendering success.
