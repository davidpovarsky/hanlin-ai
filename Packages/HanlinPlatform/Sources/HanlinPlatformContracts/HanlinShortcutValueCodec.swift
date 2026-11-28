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

    /// Native homogeneous Shortcuts lists avoid an intermediate String/JSON
    /// conversion. Nested or mixed values continue to use the existing JSON input.
    public enum NativeList: Sendable {
        case text([String])
        case integers([Int])
        case numbers([Double])
        case booleans([Bool])
    }

    public static func decodeNativeList(_ input: NativeList) throws -> HanlinValue {
        switch input {
        case .text(let values):
            return .array(values.map(HanlinValue.string))
        case .integers(let values):
            return .array(try values.enumerated().map { index, value in
                guard let integer = Int64(exactly: value) else {
                    throw HanlinContractError.integerOutOfRange(
                        value: String(value), destination: "Int64", path: "/\(index)")
                }
                return .integer(integer)
            })
        case .numbers(let values):
            return .array(try values.map(HanlinValue.finiteNumber))
        case .booleans(let values):
            return .array(values.map(HanlinValue.bool))
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
