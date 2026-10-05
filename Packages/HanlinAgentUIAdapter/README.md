# HanlinAgentUIAdapter

`HanlinAgentUIAdapter` is a boundary-isolated adapter package connecting the **Hanlin AI Platform** to the standalone **AgentUI SDK** (`StreamChatAI-iOS-Demo`).

## Purpose & Architecture

1. **Clean Seam**:
   - `HanlinAgentUIAdapter` conforms to `AgentUIRuntimeAdapter`, translating Hanlin Agent queries into typed `AgentUIEvent` streams (`.activityStarted`, `.assistantTextDelta`, `.toolExecution`, etc.).
   - `HanlinPresentationMapping` converts Hanlin platform models (`HanlinEmbeddedPresentationDescriptor`, `HanlinEmbeddedSizingPreference`, `HanlinExpansionDescriptor`, `HanlinEmbeddedResultPayload`, `HanlinToolExecutionPresentationDescriptor`) into AgentUI presentation contracts (`AgentEmbeddedPresentationDescriptor`, `AgentToolExecution`, `AgentEmbeddedPayload`).
   - `HanlinEmbeddedResultSessionWrapper` allows Hanlin Mini App view controllers/views (Swift, ScriptUI, NativeScript, Expo) to be hosted inside `AgentEmbeddedResultHost` and `AgentEmbeddedSurfaceRegistry`.
   - `HanlinHostActionsBridge` implements `AgentHostActions` to bridge link opening and host-level navigation without tight coupling.

2. **Experimental Screen**:
   - `HanlinAgentChatScreen` provides a side-by-side experimental chat screen powered by AgentUI SDK.
   - The legacy `ChatView` remains untouched and 100% authoritative for the current production pipeline.

## Usage in Host App

```swift
import HanlinAgentUIAdapter

// To open the experimental chat screen in SwiftUI:
HanlinAgentChatScreen()
```

## Adding as Local Package

In `AI_HLY.xcodeproj`, add `Packages/HanlinAgentUIAdapter` as an `XCLocalSwiftPackageReference` or use SwiftPM:

```swift
.package(path: "Packages/HanlinAgentUIAdapter")
```
