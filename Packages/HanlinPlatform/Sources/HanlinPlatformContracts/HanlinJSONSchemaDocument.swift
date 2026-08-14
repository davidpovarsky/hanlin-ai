import Foundation

public struct HanlinSchemaDialect: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme,
              !scheme.isEmpty
        else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(validating rawValue: String) throws {
        guard let value = Self(rawValue: rawValue) else {
            throw HanlinContractError.invalidSchema(
                reason: "schema dialect must be an absolute URI"
            )
        }
        self = value
    }

    public static let draft2020_12 = HanlinSchemaDialect(
        uncheckedRawValue: "https://json-schema.org/draft/2020-12/schema"
    )

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }
}

public enum HanlinSchemaFindingSeverity: String, Codable, Hashable, Sendable {
    case information
    case warning
    case error
}

public struct HanlinSchemaFinding: Codable, Hashable, Sendable {
    public let severity: HanlinSchemaFindingSeverity
    public let keyword: String?
    public let path: String
    public let message: String

    public init(
        severity: HanlinSchemaFindingSeverity,
        keyword: String? = nil,
        path: String,
        message: String
    ) {
        self.severity = severity
        self.keyword = keyword
        self.path = path
        self.message = message
    }
}

public struct HanlinJSONSchemaDocument: Codable, Hashable, Sendable {
    public let dialect: HanlinSchemaDialect
    public let root: HanlinJSONValue
    public let contentHash: String?
    public let sourceProviderInstanceID: HanlinProviderInstanceID?
    public let findings: [HanlinSchemaFinding]

    public init(
        dialect: HanlinSchemaDialect,
        root: HanlinJSONValue,
        contentHash: String? = nil,
        sourceProviderInstanceID: HanlinProviderInstanceID? = nil,
        findings: [HanlinSchemaFinding] = []
    ) throws {
        guard case var .object(members) = root else {
            throw HanlinContractError.invalidSchema(
                reason: "a JSON Schema document root must be an object"
            )
        }
        if let declared = members["$schema"] {
            guard case let .string(value) = declared else {
                throw HanlinContractError.invalidSchema(
                    reason: "$schema must be a string URI"
                )
            }
            guard value == dialect.rawValue else {
                throw HanlinContractError.invalidSchema(
                    reason: "declared $schema conflicts with the explicit dialect"
                )
            }
        } else {
            members["$schema"] = .string(dialect.rawValue)
        }
        if let contentHash {
            guard contentHash.utf8.count == 64,
                  contentHash.utf8.allSatisfy({ byte in
                      (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
                  })
            else {
                throw HanlinContractError.invalidSchema(
                    reason: "schema content hash must be 64 lowercase hexadecimal characters"
                )
            }
        }
        self.dialect = dialect
        self.root = .object(members)
        self.contentHash = contentHash
        self.sourceProviderInstanceID = sourceProviderInstanceID
        self.findings = findings
    }

    public static func decodeCanonicalJSON(
        _ data: Data,
        defaultDialect: HanlinSchemaDialect? = nil,
        limits: HanlinValueLimits = .canonical
    ) throws -> HanlinJSONSchemaDocument {
        let root = try HanlinJSONValue.decodeCanonicalJSON(data, limits: limits)
        guard case let .object(members) = root else {
            throw HanlinContractError.invalidSchema(
                reason: "a JSON Schema document root must be an object"
            )
        }
        let dialect: HanlinSchemaDialect
        if let declared = members["$schema"] {
            guard case let .string(value) = declared else {
                throw HanlinContractError.invalidSchema(
                    reason: "$schema must be a string URI"
                )
            }
            dialect = try HanlinSchemaDialect(validating: value)
        } else if let defaultDialect {
            dialect = defaultDialect
        } else {
            throw HanlinContractError.invalidSchema(
                reason: "schema dialect is required when the document omits $schema"
            )
        }
        return try HanlinJSONSchemaDocument(dialect: dialect, root: root)
    }

    public func canonicalJSONData(
        limits: HanlinValueLimits = .canonical
    ) throws -> Data {
        try root.canonicalJSONData(limits: limits)
    }
}
