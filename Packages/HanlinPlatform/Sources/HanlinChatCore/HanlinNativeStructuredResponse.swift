import AISDKProvider
import AISDKProviderUtils
import Foundation
import HanlinPlatformContracts
import SwiftAISDK

public enum HanlinNativeStructuredResponseError: String, Error, Sendable {
    case unsupportedProviderOrModel, invalidResponse, incompleteResponse, outputLimitExceeded
}

/// An explicit MODEL response contract in the existing engine, not a tool result or prose detector.
/// The host supplies official A2UI validation; no renderer or competing message store lives here.
public struct HanlinNativeStructuredResponse: Sendable {
    public static let modelID = "gpt-6.1-terra"
    public static let protocolVersion = "1.0"
    public let messageID: UUID
    private let validateCompleteParts: @MainActor @Sendable ([HanlinChatStructuredPart]) throws -> Void

    public init(messageID: UUID,
                validateCompleteParts: @escaping @MainActor @Sendable ([HanlinChatStructuredPart]) throws -> Void) {
        self.messageID = messageID
        self.validateCompleteParts = validateCompleteParts
    }

    /// A capability query is not an advertisement that an ordinary prose run emits parts.
    /// Only this concrete, direct Responses model has a verified production request mapping.
    public static func supports(_ descriptor: HanlinAISDKProviderDescriptor) -> Bool {
        descriptor.kind == .openAIResponses && descriptor.modelID == modelID
            && descriptor.baseURL.scheme == "https" && descriptor.baseURL.host == "api.openai.com"
            && descriptor.baseURL.path == "/v1" && descriptor.baseURL.user == nil
            && descriptor.baseURL.password == nil
    }

    /// This is a provider-wire projection of the canonical parts, never a second transcript format.
    /// Model part keys are local grouping labels; message/part UUIDs are issued by the host/adapter.
    func specification() -> Output.Specification<JSONValue, JSONValue> {
        let nullableString: JSONValue = .object(["type": .array([.string("string"), .string("null")])])
        let item: JSONValue = .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object([
                "part": .object(["type": .string("string"), "pattern": .string("^[A-Za-z0-9_-]+$"),
                    "description": .string("Stable local part key. Use a new key for each text segment; reuse an A2UI key for all messages updating the same result.")]),
                "kind": .object(["type": .string("string"), "enum": .array([.string("text"), .string("a2ui")])]),
                "text": nullableString,
                "a2uiJSON": .object(["type": .array([.string("string"), .string("null")]),
                    "description": .string("One complete official A2UI 1.0 JSON message, including version, using the host's approved catalog. Null for text parts.")])
            ]),
            "required": .array(["part", "kind", "text", "a2uiJSON"].map(JSONValue.string))
        ])
        let schema: JSONValue = .object([
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(["parts": .object([
                "type": .string("array"), "minItems": .number(1), "maxItems": .number(128), "items": item
            ])]),
            "required": .array([.string("parts")])
        ])
        return Output.object(schema: Schema<JSONValue>(jsonSchemaResolver: { schema }, validator: { value in
            do {
                let bytes: Data
                if let value = value as? JSONValue { bytes = try JSONEncoder().encode(value) }
                else { bytes = try JSONSerialization.data(withJSONObject: value) }
                _ = try Self.decodeWire(bytes)
                return .success(value: try JSONDecoder().decode(JSONValue.self, from: bytes))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: HanlinNativeStructuredResponseError.invalidResponse))
            }
        }), name: "hanlin_chat_parts_v1", description: "Ordered text and official A2UI 1.0 model output")
    }

    /// Called only for complete final output. Output.object's repaired partial values are never used.
    func decodeComplete(_ text: String) async throws -> [HanlinChatStructuredPart] {
        do {
            let values = try Self.decodeWire(Data(text.utf8))
            var identities = [String: UUID]()
            var ordering = HanlinChatStructuredPartSequence()
            var parts = [HanlinChatStructuredPart]()
            for (index, value) in values.enumerated() {
                try Task.checkCancellation()
                guard case .object(let item) = value, case .string(let key)? = item["part"],
                      case .string(let kind)? = item["kind"] else { throw HanlinNativeStructuredResponseError.invalidResponse }
                let partID = identities[key] ?? UUID()
                identities[key] = partID
                let payload: HanlinChatStructuredPart.Payload
                if kind == "text", case .string(let text)? = item["text"] { payload = .textDelta(text) }
                else if kind == "a2ui", case .string(let json)? = item["a2uiJSON"] {
                    payload = .a2uiMessage(protocolVersion: Self.protocolVersion, json: Data(json.utf8))
                } else { throw HanlinNativeStructuredResponseError.invalidResponse }
                let part = try HanlinChatStructuredPart(messageID: messageID, partID: partID,
                    sequence: UInt64(index), payload: payload)
                guard try ordering.admit(part) else { throw HanlinNativeStructuredResponseError.invalidResponse }
                parts.append(part)
            }
            // The existing official A2UI validator must accept the complete batch before any
            // canonical part is published. Validation itself must not activate host actions.
            try await validateCompleteParts(parts)
            try Task.checkCancellation()
            return parts
        } catch is CancellationError { throw CancellationError() }
        catch let error as HanlinNativeStructuredResponseError { throw error }
        catch { throw HanlinNativeStructuredResponseError.invalidResponse }
    }

    private static func decodeWire(_ bytes: Data) throws -> [HanlinJSONValue] {
        guard bytes.count <= 1_048_576 else { throw HanlinNativeStructuredResponseError.outputLimitExceeded }
        let value = try HanlinJSONValue.decodeCanonicalJSON(bytes)
        guard case .object(let root) = value, Set(root.keys) == ["parts"],
              case .array(let parts)? = root["parts"], !parts.isEmpty, parts.count <= 128 else {
            throw HanlinNativeStructuredResponseError.invalidResponse
        }
        for value in parts {
            guard case .object(let item) = value, Set(item.keys) == ["part", "kind", "text", "a2uiJSON"],
                  case .string(let key)? = item["part"], !key.isEmpty, key.utf8.count <= 128,
                  key.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 }),
                  case .string(let kind)? = item["kind"] else { throw HanlinNativeStructuredResponseError.invalidResponse }
            if kind == "text" {
                guard case .string(let text)? = item["text"], !text.isEmpty,
                      case .null? = item["a2uiJSON"] else { throw HanlinNativeStructuredResponseError.invalidResponse }
            } else if kind == "a2ui" {
                guard case .null? = item["text"], case .string(let json)? = item["a2uiJSON"],
                      case .object = try HanlinJSONValue.decodeCanonicalJSON(Data(json.utf8)) else {
                    throw HanlinNativeStructuredResponseError.invalidResponse
                }
            } else { throw HanlinNativeStructuredResponseError.invalidResponse }
        }
        // Each text item is a complete segment. Reusing it across a surface would move
        // trailing text ahead of that surface in the canonical presentation projection.
        var textKeys = Set<String>()
        for value in parts {
            if case .object(let item) = value, case .string("text")? = item["kind"],
               case .string(let key)? = item["part"], !textKeys.insert(key).inserted {
                throw HanlinNativeStructuredResponseError.invalidResponse
            }
        }
        return parts
    }
}
