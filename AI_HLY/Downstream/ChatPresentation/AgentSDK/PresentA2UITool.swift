#if HANLIN_A2UI_POC
import Foundation
import HanlinPlatformContracts

/// A native result producer for the existing official renderer, not another UI engine.
/// Actions acquire authority only after the canonical Host receipt is durably saved.
struct PresentA2UITool: NativeTool {
    let name = "present_a2ui"
    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: "Show interactive content",
            summary: "Display interactive forms, source-linked image galleries and link previews in this conversation.",
            categories: ["presentation"], keywords: ["a2ui", "form", "interactive", "image", "gallery", "media", "link preview"],
            systemImage: "rectangle.and.hand.point.up.left",
            presentationProfile: .modernNative(toolName: name, kind: .generic,
                systemImage: "rectangle.and.hand.point.up.left",
                runningTitle: "Preparing interactive content", completedTitle: "Interactive content",
                visibleArgumentKeys: []))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name,
            description: "Display a complete batch of official A2UI 1.0 envelopes in this tool result. Each messages item is one exact JSON envelope. User actions return as a new chat turn; they never directly execute code.\n" + HanlinMediaCatalog.modelGuidance,
            parameters: NativeToolSchema.object(properties: [
                "messages": NativeToolSchema.stringArray(description: "Complete official JSON envelopes in order.", maximumItems: 64)
            ], required: ["messages"]))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            try Task.checkCancellation()
            let args = try NativeToolJSON.validatedDictionary(from: argumentsJSON, allowedKeys: ["messages"])
            let messages = try NativeToolJSON.strictStringArray(args, "messages").map { Data($0.utf8) }
            guard !messages.isEmpty, messages.count <= 64,
                  messages.reduce(0, { $0 + $1.count }) <= 1_048_576 else {
                throw HanlinA2UICompleteBatchValidator.Failure.resourceLimit
            }
            let message = UUID(), part = UUID()
            let parts = try messages.enumerated().map { index, bytes in
                try HanlinChatStructuredPart(messageID: message, partID: part, sequence: UInt64(index),
                    payload: .a2uiMessage(protocolVersion: "1.0", json: bytes))
            }
            try HanlinA2UICompleteBatchValidator.validate(parts)
            try Task.checkCancellation()
            return NativeToolResult(modelText: "The official interactive result is displayed in this conversation.",
                userText: "Interactive content", outcome: .succeeded,
                embeddedPayload: try .officialA2UI(messages: messages, title: "Interactive content"),
                isStoreEligible: true)
        } catch {
            return NativeToolResult(modelText: "Interactive content was rejected: \(error.localizedDescription)",
                outcome: .invalidArguments)
        }
    }
}
#endif
