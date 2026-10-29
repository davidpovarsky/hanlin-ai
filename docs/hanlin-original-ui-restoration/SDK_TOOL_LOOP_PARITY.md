# Swift AI SDK Tool-Loop Parity & Engine Routing

- **Package Target**: `Packages/HanlinPlatform/Sources/HanlinChatCore` (`HanlinAISDKAgentEngine.swift`, `HanlinAISDKModels.swift`, `HanlinAISDKProviderFactory.swift`)
- **App Integration**: `AI_HLY/Services/ChatServices/APIManager.swift` (`processSDKAgentEngine`), `AI_HLY/Downstream/AgentSkills/HanlinAISDKToolAdapter.swift`, `AI_HLY/Downstream/ChatPresentation/ClassicChatAgentProjection.swift`

---

## 1. Explicit Engine Routing & Elimination of Dual-Loop Fallback (`G4`)

`APIManager.sendStreamRequest` routes every request through one explicit execution path and records `agentEngineKind` in `AgentDiagnosticsSession`:

| Route | Condition | Execution Method | `agentEngineKind` | Tool Loop Owner |
|---|---|---|---|---|
| **Local Model** | `route == .localModel` (`company == "LOCAL"`) | `processLocalStream` | `"local"` | Local LLM runner (no remote recursive loop) |
| **Image Generation** | `route == .remoteImageGeneration` | `processImageGeneration` | `"image"` | Dedicated image generation endpoint |
| **Remote Agent / Tool-Capable** | `route == .remoteText && useTools` | `processSDKAgentEngine` | `"swift_ai_sdk"` | `HanlinAISDKAgentEngine.stream` -> `SwiftAISDK.streamText` (`stopWhen: [stepCountIs(effectiveMaxSteps)]`, `effectiveMaxSteps = max(maxSteps ?? 40, 1)`) |
| **Remote Plain Text** | `route == .remoteText && !useTools` | `processRemoteStream(..., useTools: false, allowToolRecursion: false)` | `"plain_text"` | Single-pass streaming text only (`allowToolRecursion` forced `false`) |

### Proof of Legacy Recursive Loop Elimination
1. In `APIManager.sendStreamRequest` (`AI_HLY/Services/ChatServices/APIManager.swift`), when `useTools == true`, `processSDKAgentEngine` is called unconditionally.
2. When `HanlinAISDKProviderFactory.createLanguageModel` returns `nil` or throws (e.g. missing API key or invalid base URL), `processSDKAgentEngine` emits a typed `StreamData(errorMessage: ...)` and records `"failed"` in `AgentDiagnosticsRecorder` — it **never** falls back to `processRemoteStream(..., useTools: true)`.
3. When `useTools == false`, `processRemoteStream` is invoked with `useTools: false, allowToolRecursion: false`.

---

## 2. Typed Multimodal & Role Conversion (`G5`)

### P0 Multimodal Bug Fixed
Previously, `processSDKAgentEngine` converted `formattedMessages: [[String: Any]]` using `msg["content"] as? String ?? ""`, which replaced multimodal user content arrays (`[["type": "text", ...], ["type": "image_url", ...]]`) with `""`.

`APIManager.convertFormattedMessagesToSDKMessages(_:)` now converts every message losslessly into `[HanlinAISDKMessage]`:
- `role == "system"` or `role == "developer"`: extracted and joined into `baseSystemPrompt` (or `.system` message).
- `content as? String`: mapped to `[.text(stringContent)]`.
- `content as? [[String: Any]]`:
  - `type == "text"` / `"input_text"`: mapped to `.text(textValue)`.
  - `type == "image_url"`:
    - `data:<mime>;base64,<payload>` URLs are decoded into `.imageData(decodedData, mimeType: parsedMimeType)`.
    - `http://` / `https://` URLs are mapped to `.imageURL(remoteURL)`.
  - `type == "file"`: decoded into `.fileData(decodedData, mimeType: mimeType, filename: filename)`.
- In `HanlinAISDKAgentEngine.convertMessages`, `.imageData`, `.imageURL`, `.fileData`, and `.text` parts are mapped directly to `LanguageModelV3UserMessagePart.text` and `.file(LanguageModelV3FilePart(data: .data(...) / .url(...), mediaType: ...))`.

---

## 3. Complete `TextStreamPart` -> `HanlinAISDKStreamEvent` Parity (`G4`, `G5`)

| `SwiftAISDK.TextStreamPart` Case | `HanlinAISDKStreamEvent` Case | Downstream Handling in `APIManager` & `ClassicChatAgentProjection` |
|---|---|---|
| `.startStep(request:warnings:)` | `.stepStarted(stepIndex: Int)` | Emits `.planningUpdated` / `.roundStarted` |
| `.textDelta(id:delta:providerMetadata:)` | `.textDelta(String)` | Sanitized via `stripRawThinkTags` and streamed into `assistantMessage.text` |
| `.reasoningDelta(id:delta:providerMetadata:)` | `.reasoningDelta(String)` | Sanitized via `ProgressSummarySanitizer.sanitizeProviderReasoningSummary` and streamed into `assistantMessage.reasoning` |
| `.toolCall(TypedToolCall)` | `.toolCallStarted(callId:toolName:argumentsJSON:)` | Tracked by `callId`; updates operational state & `AgentRun` step |
| `.toolResult(TypedToolResult)` | `.toolCallFinished(callId:toolName:resultJSON:isError:)` | Inspects nested `isError` / `outcome == "failed"`; projects search/code/HTML/nativeUI/MCP results |
| `.toolError(TypedToolError)` | `.toolCallFinished(..., isError: true)` | Marks tool step `.failed` and returns structured error JSON to model for recovery |
| `.toolApprovalRequest(ToolApprovalRequestOutput)` | `.toolApprovalRequest(approvalId:toolCallId:toolName:argumentsJSON:)` | Emits `.approvalRequested` event into `AgentRun` and appends notice to `toolContent` |
| `.toolOutputDenied(ToolOutputDenied)` | `.toolOutputDenied(callId:toolName:)` | Emits `.toolCallFailed(..., errorSummary: "Tool output was denied.")` |
| `.source(LanguageModelV3Source)` | `.source(id:url:title:)` | `ClassicChatAgentProjection.appendProviderSource` populates `assistantMessage.resources` and `role == "search"` row |
| `.file(LanguageModelV3File)` | `.file(mediaType:data:)` | `ClassicChatAgentProjection.appendProviderFile` appends `UIImage` to `assistantMessage.images` or file URL to `uploadDocument` |
| `.finishStep(response:usage:finishReason:providerMetadata:)` | `.stepFinished(stepIndex:finishReason:)` | Records step completion in `AgentDiagnosticsRecorder` |
| `.finish( finishReason:totalUsage:)` | `.finished(finishReason:usage:)` | Finalizes turn, records token usage, emits `isComplete = true` |
| `.error(Error)` | `.error(String)` | Propagates error to `errorMessageView()` |
