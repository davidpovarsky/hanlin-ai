# Codex instructions: Native Tool Search + Native UI Foundation

Repository: `davidpovarsky/hanlin-ai`

Target branch: create a new branch from the latest working branch after localization is merged/completed, for example:

```text
native-tool-search-foundation
```

## Goal

Add a separate Swift-only native tools layer with progressive tool loading:

1. The model always sees only a tiny `tool_search` tool.
2. When the model needs a capability, it calls `tool_search`.
3. Swift searches the native tool catalog.
4. The next model step receives full schemas only for the matching tools.
5. If the model calls one of those tools, Swift executes it.
6. Tool results can return both model text and native UI blocks rendered in the chat.

No JS, no TS, no runtime scripting engine.

## Absolute restrictions

Do only and exactly this task.

Do not redesign the app.
Do not refactor unrelated code.
Do not rename providers, models, files, targets or existing types.
Do not change AI provider behavior except the minimum required tool-loading integration.
Do not change localization except if a compiler error requires adding a tiny key.
Do not change existing map/calendar/health/search/code/canvas tools except to append our extension hooks.
Do not open a PR.
Do not merge branches.
Do not delete existing Chinese or English behavior.
Do not add package dependencies.
Do not introduce JS/TS.
Do not use WebView for these native UI blocks.

Use system-native SwiftUI components as much as possible. Do not create a hand-designed UI with lots of custom HStack/VStack layout. Prefer `GroupBox`, `Label`, `Button`, `Link`, `DisclosureGroup`, `LabeledContent`, `ControlGroup`, `ProgressView`, and other system components.

## Files to add

Copy the whole folder:

```text
AI_HLY/NativeAgentExtensions/
```

into the repository at:

```text
AI_HLY/NativeAgentExtensions/
```

Ensure every Swift file in that folder is included in the `AI_HLY` app target. If the Xcode project uses file-system synchronized groups, adding the files under `AI_HLY` may be enough. If the build cannot see these files, add them to the app target sources in the Xcode project. Do not edit the project file unless necessary.

## Required source integration points

Keep source changes minimal.

### 1. ChatMessages stored property

Find the SwiftData model/class `ChatMessages`.

Add one stored optional string property:

```swift
var nativeUIBlocksJSON: String?
```

If `ChatMessages` has a custom initializer, add a parameter with default `nil` and assign it:

```swift
nativeUIBlocksJSON: String? = nil
```

and inside the initializer:

```swift
self.nativeUIBlocksJSON = nativeUIBlocksJSON
```

Do not add a transformable array property. Use this JSON string so persistence stays simple.

The extension file `ChatMessages+NativeUI.swift` depends on this stored property and provides:

```swift
msg.nativeUIBlocks
msg.appendNativeUIBlocks(...)
```

### 2. APIManager StreamData

In `AI_HLY/Services/ChatServices/APIManager.swift`, find `struct StreamData`.

Add:

```swift
var native_ui: [NativeUIBlock]?
```

Do not remove any existing fields.

### 3. APIManager native UI buffer

In `class APIManager`, next to the existing temporary buffers such as `locationsInfo`, `storeRouteInfo`, `healthCard`, `codeBlock`, `knowledgeCard`, and `canvasInfo`, add:

```swift
private var nativeUIBlocks: [NativeUIBlock]?
```

### 4. processRemoteModel must carry loaded native tool schemas

Find the remote-model processing function. It is the function that builds `requestBody`, adds `requestBody["tools"]`, parses streaming `tool_calls`, executes the large `switch functionName`, then recursively calls itself after a tool result.

Add a parameter with a default value:

```swift
nativeLoadedToolNames: [String] = []
```

When this function recursively calls itself after tool execution, pass the updated `nativeLoadedToolNames`.

When other callers call this function, they do not need to pass it because it has a default.

### 5. Add our schemas to requestBody["tools"]

In the existing block that does:

```swift
let tools = buildMemoryTools(...)
requestBody["tools"] = tools
```

change it minimally to append our extension schemas.

Use this pattern:

```swift
var tools = buildMemoryTools(
    memoryEnabled: memoryEnabled,
    mapEnabled: mapEnabled,
    calendarEnabled: calendarEnabled,
    searchEnabled: searchEnabled,
    knowledgeEnabled: knowledgeEnabled,
    codeEnabled: codeEnabled,
    healthEnabled: healthEnabled,
    weatherEnabled: weatherEnabled,
    canvasEnabled: canvasEnabled
)

tools.append(contentsOf: NativeToolBridge.schemasForRequest(loadedToolNames: nativeLoadedToolNames))
requestBody["tools"] = tools
```

If Swift infers `tools` as `let`, change only `let` to `var`.

This means:

- `tool_search` is always available when tool use is enabled.
- Real native tool schemas are only included after `tool_search` requested them.

### 6. Execute native tools in the existing switch default

Find the large `switch functionName` that handles built-in tools like maps, routes, calendar, health, code, canvas, etc.

Do not add many new `case` blocks.

In the `default:` branch, before it sets `toolResult = "Unknown"`, insert:

```swift
let nativeContext = NativeToolExecutionContext(
    localeIdentifier: currentLanguage,
    modelContext: self.context
)

if let nativeResult = await NativeToolBridge.executeIfNativeTool(
    name: functionName,
    argumentsJSON: functionArguments,
    context: nativeContext
) {
    useFunctionName = functionName
    toolResult = nativeResult.modelText
    toolResultFront = nativeResult.userText ?? nativeResult.modelText

    if !nativeResult.uiBlocks.isEmpty {
        if self.nativeUIBlocks == nil { self.nativeUIBlocks = [] }
        self.nativeUIBlocks?.append(contentsOf: nativeResult.uiBlocks)
    }

    if !nativeResult.deferredToolNames.isEmpty {
        nextNativeLoadedToolNames = nativeResult.deferredToolNames
    }

    break
}
```

You must declare `nextNativeLoadedToolNames` before the switch is used:

```swift
var nextNativeLoadedToolNames = nativeLoadedToolNames
```

If the existing code structure requires a different nearby location for this variable, keep the same meaning: `tool_search` updates it, and the recursive model request receives it.

After this native branch, keep the old Unknown fallback unchanged.

### 7. Yield native UI blocks after tool execution

Find the existing `continuation.yield(StreamData(...))` that yields:

```swift
locations_info: self.locationsInfo,
route_info: self.storeRouteInfo,
events: self.events,
htmlContent: self.htmlContent,
health_info: self.healthCard,
code_info: self.codeBlock,
knowledge_card: self.knowledgeCard,
canvas_info: self.canvasInfo
```

Add:

```swift
native_ui: self.nativeUIBlocks,
```

Then after the yield, where existing buffers are reset to `nil`, add:

```swift
self.nativeUIBlocks = nil
```

### 8. Recursive call must use nextNativeLoadedToolNames

In the recursive `processRemoteModel(...)` call after a tool result, pass:

```swift
nativeLoadedToolNames: nextNativeLoadedToolNames
```

This is critical. Without it, `tool_search` will find tools but their schemas will not be loaded in the next model step.

### 9. ChatView stream handler

In `ChatView.swift`, in the stream loop where `StreamData` is applied to `assistantMessage`, add:

```swift
if let nativeUI = data.native_ui, !nativeUI.isEmpty {
    assistantMessage.appendNativeUIBlocks(nativeUI)
    updated = true
}
```

Place it near the existing handling for `locations_info`, `route_info`, `events`, `health_info`, `code_info`, `knowledge_card`, and `canvas_info`.

### 10. Pass native UI blocks into ChatBubbleView

In `ChatView.swift`, find the `ChatBubbleView(...)` initializer call.

Add a new argument:

```swift
nativeUIBlocks: msg.nativeUIBlocks,
```

Do not remove any existing arguments.

### 11. ChatBubbleView rendering

Find the `ChatBubbleView` struct and its initializer.

Add a stored property:

```swift
let nativeUIBlocks: [NativeUIBlock]
```

Add an initializer parameter with a default so other call sites do not break:

```swift
nativeUIBlocks: [NativeUIBlock] = []
```

Assign it.

In the message body, near the existing rich blocks such as maps, routes, resources, health cards, code blocks, knowledge cards, canvas, etc., render:

```swift
if !nativeUIBlocks.isEmpty {
    NativeUIRenderer(blocks: nativeUIBlocks)
}
```

Do not redesign `ChatBubbleView`. Just add this block at a sensible place after tool/result cards and before footer/actions.

### 12. Confirm build behavior

Run:

```bash
xcodebuild -project AI_HLY.xcodeproj -scheme AI_HLY -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

If this environment cannot build iOS, state exactly why. Do not fake success.

## Expected behavior to test manually

1. Ask: `what tools can help search Jewish texts?`
   - Model should call `tool_search`.
   - App should return `sefaria_search` / `sefaria_get_source` as matches.
   - Recursive request should load these schemas.

2. Ask: `find a Jewish source about hashavat aveidah`
   - Model should call `tool_search` if schemas are not loaded.
   - Then call `sefaria_search`.
   - Chat should show a native Sefaria result card/list.

3. Ask: `search Wikipedia for Maimonides`
   - Model should discover/load Wikipedia tools.
   - Then call `wikipedia_search` or `wikipedia_get_summary`.
   - Chat should show native Wikipedia cards.

4. Ask: `calculate 17% of 340`
   - Model should discover/load `quick_calculate`.
   - Then call it.
   - Chat should show native calculation card.

## Final Codex report must include

1. Files added.
2. Exact original files modified.
3. Confirmation that the new layer is under `AI_HLY/NativeAgentExtensions`.
4. Confirmation that only minimal source entry points were added.
5. Confirmation that `tool_search` is the always-available discovery tool.
6. Confirmation that actual native tool schemas are deferred and loaded only after `tool_search`.
7. Confirmation that Native UI uses system SwiftUI components as much as possible.
8. Build command result.
9. Any remaining compile issues, with exact errors.
10. Confirmation that no unrelated provider/model/search/map/calendar/health/canvas behavior was changed.
