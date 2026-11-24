#if canImport(FoundationModels)
import AISDKProvider
import Foundation
import FoundationModels

/// Converts the shared producer's canonical roles to native transcript entries. It never
/// stores a second conversation and never introduces a model-visible continuation prompt.
@available(iOS 27.0, macOS 27.0, *)
struct HanlinAppleToolHistory: Sendable {
    let instructions: String?
    let entries: [Transcript.Entry]
    let callIDs: Set<String>

    init(_ prompt: LanguageModelV3Prompt) throws {
        var instructions: String?
        var entries: [Transcript.Entry] = []
        var pending: [String: String] = [:]
        var callIDs: Set<String> = []
        guard !prompt.isEmpty, prompt.count <= 2_048 else { throw HanlinAppleToolBridgeError.invalidHistory }
        for (index, message) in prompt.enumerated() {
            let prefix = "hanlin_history_\(index)"
            switch message {
            case .system(let text, let options):
                guard index == 0, instructions == nil, options?.isEmpty != false else {
                    throw HanlinAppleToolBridgeError.invalidHistory
                }
                instructions = text
            case .user(let parts, let options):
                guard pending.isEmpty, options?.isEmpty != false, !parts.isEmpty else {
                    throw HanlinAppleToolBridgeError.invalidHistory
                }
                let segments = try parts.enumerated().map { offset, part -> Transcript.Segment in
                    guard case .text(let text) = part, text.providerOptions?.isEmpty != false else {
                        throw HanlinAppleProviderError.unsupportedContent
                    }
                    return .text(.init(id: prefix + "_\(offset)", content: text.text))
                }
                entries.append(.prompt(.init(id: prefix, segments: segments)))
            case .assistant(let parts, let options):
                guard pending.isEmpty, options?.isEmpty != false, !parts.isEmpty else {
                    throw HanlinAppleToolBridgeError.invalidHistory
                }
                var segments: [Transcript.Segment] = []
                var calls: [Transcript.ToolCall] = []
                for (offset, part) in parts.enumerated() {
                    switch part {
                    case .text(let text):
                        guard calls.isEmpty, text.providerOptions?.isEmpty != false else {
                            throw HanlinAppleToolBridgeError.invalidHistory
                        }
                        segments.append(.text(.init(id: prefix + "_\(offset)", content: text.text)))
                    case .toolCall(let call):
                        guard call.providerExecuted != true, call.providerOptions?.isEmpty != false,
                              Self.validIdentity(call.toolCallId), Self.validIdentity(call.toolName),
                              callIDs.insert(call.toolCallId).inserted else {
                            throw HanlinAppleToolBridgeError.invalidHistory
                        }
                        let json = try Self.normalizedJSON(call.input)
                        guard case .object = call.input else { throw HanlinAppleToolBridgeError.invalidArguments }
                        calls.append(.init(id: call.toolCallId, toolName: call.toolName,
                                           arguments: try GeneratedContent(json: json)))
                        pending[call.toolCallId] = call.toolName
                    default: throw HanlinAppleProviderError.unsupportedContent
                    }
                }
                if !segments.isEmpty { entries.append(.response(.init(id: prefix, assetIDs: [], segments: segments))) }
                if !calls.isEmpty { entries.append(.toolCalls(.init(id: prefix + "_calls", calls))) }
            case .tool(let parts, let options):
                guard options?.isEmpty != false else { throw HanlinAppleToolBridgeError.invalidHistory }
                // The pinned producer removes client-only approval responses before provider
                // conversion; the resulting empty tool message carries no model content.
                if parts.isEmpty { continue }
                for (offset, part) in parts.enumerated() {
                    guard case .toolResult(let output) = part,
                          output.providerOptions?.isEmpty != false,
                          pending.removeValue(forKey: output.toolCallId) == output.toolName else {
                        throw HanlinAppleToolBridgeError.invalidHistory
                    }
                    let text: String
                    switch output.output {
                    case .text(let value, let options), .errorText(let value, let options):
                        guard options?.isEmpty != false else { throw HanlinAppleProviderError.unsupportedContent }
                        text = value
                    case .executionDenied(let reason, let options):
                        guard options?.isEmpty != false else { throw HanlinAppleProviderError.unsupportedContent }
                        text = reason ?? "Tool execution was denied."
                    default: throw HanlinAppleProviderError.unsupportedContent
                    }
                    // Native ToolOutput has an id and toolName; preserve the canonical call identity
                    // rather than generating new identities when rebuilding the provider request.
                    entries.append(.toolOutput(.init(id: output.toolCallId, toolName: output.toolName,
                        segments: [.text(.init(id: prefix + "_\(offset)", content: text))])))
                }
            }
        }
        guard pending.isEmpty, let last = entries.last else { throw HanlinAppleToolBridgeError.invalidHistory }
        switch last {
        case .prompt, .toolOutput: break
        default: throw HanlinAppleToolBridgeError.invalidHistory
        }
        self.instructions = instructions
        self.entries = entries
        self.callIDs = callIDs
    }

    static func validIdentity(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    /// This is explicitly normalized JSON, never evidence of original model token spelling.
    static func normalizedJSON(_ value: JSONValue) throws -> String {
        var remaining = 4_096
        try rejectNumbers(value, depth: 0, remaining: &remaining)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= 65_536, let result = String(data: data, encoding: .utf8) else {
            throw HanlinAppleToolBridgeError.invalidArguments
        }
        return result
    }

    static func generatedValue(_ value: GeneratedContent, depth: Int = 0,
                               remaining: inout Int) throws -> JSONValue {
        guard value.isComplete, depth <= 32, remaining > 0 else { throw HanlinAppleToolBridgeError.invalidArguments }
        remaining -= 1
        switch value.kind {
        case .null: return .null
        case .bool(let value): return .bool(value)
        case .string(let value):
            guard value.utf8.count <= 65_536 else { throw HanlinAppleToolBridgeError.invalidArguments }
            return .string(value)
        case .number: throw HanlinAppleToolBridgeError.numericArgumentsUnsupported
        case .array(let values):
            return .array(try values.map { try generatedValue($0, depth: depth + 1, remaining: &remaining) })
        case .structure(let properties, let keys):
            guard Set(keys).count == keys.count, Set(keys) == Set(properties.keys) else {
                throw HanlinAppleToolBridgeError.invalidArguments
            }
            var output: [String: JSONValue] = [:]
            for key in keys {
                guard let value = properties[key] else { throw HanlinAppleToolBridgeError.invalidArguments }
                output[key] = try generatedValue(value, depth: depth + 1, remaining: &remaining)
            }
            return .object(output)
        @unknown default: throw HanlinAppleToolBridgeError.invalidArguments
        }
    }

    private static func rejectNumbers(_ value: JSONValue, depth: Int, remaining: inout Int) throws {
        guard depth <= 32, remaining > 0 else { throw HanlinAppleToolBridgeError.invalidArguments }
        remaining -= 1
        switch value {
        case .number: throw HanlinAppleToolBridgeError.numericArgumentsUnsupported
        case .array(let values):
            for value in values { try rejectNumbers(value, depth: depth + 1, remaining: &remaining) }
        case .object(let values):
            for value in values.values { try rejectNumbers(value, depth: depth + 1, remaining: &remaining) }
        case .null, .bool, .string: break
        }
    }
}
#endif
