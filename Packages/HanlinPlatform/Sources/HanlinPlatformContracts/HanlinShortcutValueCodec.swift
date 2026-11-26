import Foundation

/// Shortcuts uses ordinary JSON, never Hanlin's tagged internal wire format.
/// The canonical parser preserves Int64, booleans, null and nested values and
/// rejects duplicate keys instead of silently replacing them.
public enum HanlinShortcutValueCodec {
    public enum Input: String, Codable, CaseIterable, Sendable {
        case text, json, dictionaryOrList
    }

    public enum InputError: Error, Equatable, LocalizedError, Sendable {
        case dictionaryOrListRequired

        public var errorDescription: String? {
            "The shortcut input must be a JSON dictionary or list."
        }
    }

    public static func decode(_ input: String, as format: Input) throws -> HanlinValue {
        if format == .text { return .string(input) }
        let value = try HanlinJSONValue.decodeCanonicalJSON(Data(input.utf8), limits: .unbounded)
        if format == .dictionaryOrList {
            switch value {
            case .object, .array: break
            default: throw InputError.dictionaryOrListRequired
            }
        }
        return try HanlinValue(jsonValue: value)
    }

    /// A JSON file result retains its structure when passed to the next Shortcut.
    /// Binary results are returned as files by the caller, never silently encoded.
    public static func encodeJSON(_ value: HanlinValue) throws -> Data {
        try value.jsonValue().canonicalJSONData(limits: .unbounded)
    }
}
