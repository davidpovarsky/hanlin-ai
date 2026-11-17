import Foundation

/// JSON transported by the original OpenUI runtime. This is display/form state,
/// never a permission grant, an executable script, or a substitute for Host context.
public enum PresentationValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([PresentationValue])
    case object([String: PresentationValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([PresentationValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: PresentationValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value)
        case .object(let value): try c.encode(value)
        }
    }

    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var array: [PresentationValue]? { if case .array(let value) = self { value } else { nil } }
    public var object: [String: PresentationValue]? { if case .object(let value) = self { value } else { nil } }

    public var displayText: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted(.number.precision(.fractionLength(0...4)))
        case .bool(let value): value ? "true" : "false"
        case .null: ""
        case .array, .object: (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? ""
        }
    }
}
