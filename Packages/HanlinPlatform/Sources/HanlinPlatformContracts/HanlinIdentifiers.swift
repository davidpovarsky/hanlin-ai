import Foundation

public protocol HanlinStringIdentifier:
    RawRepresentable,
    Codable,
    Hashable,
    CustomStringConvertible,
    Sendable
where RawValue == String {
    static var identifierKind: String { get }
    init(validating rawValue: String) throws
}

extension HanlinStringIdentifier {
    public init?(rawValue: String) {
        guard let value = try? Self(validating: rawValue) else {
            return nil
        }
        self = value
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        try self.init(validating: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

private enum HanlinIdentifierValidator {
    static func validate(
        _ value: String,
        kind: String
    ) throws {
        if let reason = validationFailure(for: value) {
            throw HanlinContractError.invalidIdentifier(
                kind: kind,
                value: value,
                reason: reason
            )
        }
    }

    private static func validationFailure(for value: String) -> String? {
        guard !value.isEmpty else {
            return "value is empty"
        }
        guard value.utf8.count <= 255 else {
            return "UTF-8 representation exceeds 255 bytes"
        }
        guard value.utf8.allSatisfy({ $0 < 128 }) else {
            return "only canonical ASCII identifiers are accepted"
        }
        guard let first = value.utf8.first, let last = value.utf8.last else {
            return "value is empty"
        }
        guard isLowercaseLetterOrDigit(first), isLowercaseLetterOrDigit(last) else {
            return "value must begin and end with a lowercase ASCII letter or digit"
        }

        var previousWasSeparator = false
        for byte in value.utf8 {
            if isLowercaseLetterOrDigit(byte) {
                previousWasSeparator = false
                continue
            }
            let isSeparator = byte == 45 || byte == 46 || byte == 95
            guard isSeparator else {
                return "allowed characters are lowercase ASCII letters, digits, '.', '-', and '_'"
            }
            guard !previousWasSeparator else {
                return "adjacent separators are not canonical"
            }
            previousWasSeparator = true
        }
        return nil
    }

    private static func isLowercaseLetterOrDigit(_ byte: UInt8) -> Bool {
        (97 ... 122).contains(byte) || (48 ... 57).contains(byte)
    }
}

public struct HanlinAppID: HanlinStringIdentifier {
    public static let identifierKind = "app"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinPackageID: HanlinStringIdentifier {
    public static let identifierKind = "package"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinModuleID: HanlinStringIdentifier {
    public static let identifierKind = "module"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinRouteID: HanlinStringIdentifier {
    public static let identifierKind = "route"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinActionID: HanlinStringIdentifier {
    public static let identifierKind = "action"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinToolID: HanlinStringIdentifier {
    public static let identifierKind = "tool"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinCapabilityID: HanlinStringIdentifier {
    public static let identifierKind = "capability"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinPermissionDecisionID: HanlinStringIdentifier {
    public static let identifierKind = "permission-decision"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinSessionID: HanlinStringIdentifier {
    public static let identifierKind = "session"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinCallbackID: HanlinStringIdentifier {
    public static let identifierKind = "callback"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinObjectHandleID: HanlinStringIdentifier {
    public static let identifierKind = "object-handle"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinRequestID: HanlinStringIdentifier {
    public static let identifierKind = "request"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinMCPServerID: HanlinStringIdentifier {
    public static let identifierKind = "mcp-server"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}

public struct HanlinPublisherID: HanlinStringIdentifier {
    public static let identifierKind = "publisher"
    public let rawValue: String
    public init(validating rawValue: String) throws {
        try HanlinIdentifierValidator.validate(rawValue, kind: Self.identifierKind)
        self.rawValue = rawValue
    }
}
