import Foundation
import HanlinPlatformContracts

public enum HanlinScriptingSourceFormat: String, Codable, Hashable, Sendable {
    case scripting
    case zip
}

public struct HanlinImportedPackageSource: Codable, Hashable, Sendable {
    public let originalFileName: String
    public let format: HanlinScriptingSourceFormat
    public let contentSHA256: String
    public let byteCount: Int64
    public let importedAt: Date
    public let trust: HanlinPackageTrust

    public init(
        originalFileName: String,
        format: HanlinScriptingSourceFormat,
        contentSHA256: String,
        byteCount: Int64,
        importedAt: Date,
        trust: HanlinPackageTrust = .localUnverified
    ) {
        self.originalFileName = originalFileName
        self.format = format
        self.contentSHA256 = contentSHA256
        self.byteCount = byteCount
        self.importedAt = importedAt
        self.trust = trust
    }
}

public enum HanlinArchiveFindingCode: String, Codable, Hashable, Sendable {
    case absolutePath
    case parentTraversal
    case drivePrefix
    case nulByte
    case symbolicLink
    case hardLink
    case unicodeCollision
    case caseCollision
    case fileCountLimit
    case depthLimit
    case compressedSizeLimit
    case uncompressedSizeLimit
    case compressionRatioLimit
    case encryptedEntry
    case unsupportedFileType
    case ambiguousManifest
    case malformedArchive
}

public enum HanlinDiagnosticSeverity: String, Codable, Hashable, Sendable {
    case information
    case warning
    case error
}

public struct HanlinArchiveFinding: Codable, Hashable, Sendable {
    public let code: HanlinArchiveFindingCode
    public let severity: HanlinDiagnosticSeverity
    public let entry: String?
    public let message: String

    public init(
        code: HanlinArchiveFindingCode,
        severity: HanlinDiagnosticSeverity,
        entry: String? = nil,
        message: String
    ) {
        self.code = code
        self.severity = severity
        self.entry = entry
        self.message = message
    }
}

public struct HanlinArchiveInspection: Codable, Hashable, Sendable {
    public let fileCount: Int
    public let directoryCount: Int
    public let compressedBytes: Int64
    public let uncompressedBytes: Int64
    public let maximumDepth: Int
    public let wrapperDirectory: String?
    public let manifestPath: String?
    public let ignoredEntries: [String]
    public let findings: [HanlinArchiveFinding]

    public init(
        fileCount: Int,
        directoryCount: Int,
        compressedBytes: Int64,
        uncompressedBytes: Int64,
        maximumDepth: Int,
        wrapperDirectory: String? = nil,
        manifestPath: String? = nil,
        ignoredEntries: [String] = [],
        findings: [HanlinArchiveFinding] = []
    ) {
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.compressedBytes = compressedBytes
        self.uncompressedBytes = uncompressedBytes
        self.maximumDepth = maximumDepth
        self.wrapperDirectory = wrapperDirectory
        self.manifestPath = manifestPath
        self.ignoredEntries = ignoredEntries
        self.findings = findings
    }

    public var isInstallable: Bool {
        !findings.contains { $0.severity == .error }
    }
}

public struct HanlinScriptingAuthor: Codable, Hashable, Sendable {
    public let name: String
    public let email: String?
    public let homepage: String?

    public init(name: String, email: String? = nil, homepage: String? = nil) {
        self.name = name
        self.email = email
        self.homepage = homepage
    }
}

public struct HanlinScriptingRemoteResource: Codable, Hashable, Sendable {
    public let url: String
    public let autoUpdateInterval: Double?
    public let hash: String?

    public init(url: String, autoUpdateInterval: Double? = nil, hash: String? = nil) {
        self.url = url
        self.autoUpdateInterval = autoUpdateInterval
        self.hash = hash
    }
}

/// Lossless `script.json` metadata. Unknown fields are retained for forward
/// compatibility but never grant capabilities or entrypoints.
public struct HanlinScriptingManifest: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
    public let description: String?
    public let localizedNames: [String: String]
    public let localizedDescriptions: [String: String]
    public let author: HanlinScriptingAuthor?
    public let contributors: [HanlinScriptingAuthor]
    public let icon: String?
    public let iconImage: String?
    public let color: String?
    public let entry: String?
    public let runInApp: Bool
    public let intentInputTypes: [String]
    public let remoteResource: HanlinScriptingRemoteResource?
    public let unknownFields: [String: HanlinJSONValue]

    public init(
        name: String,
        version: String,
        description: String? = nil,
        localizedNames: [String: String] = [:],
        localizedDescriptions: [String: String] = [:],
        author: HanlinScriptingAuthor? = nil,
        contributors: [HanlinScriptingAuthor] = [],
        icon: String? = nil,
        iconImage: String? = nil,
        color: String? = nil,
        entry: String? = nil,
        runInApp: Bool = false,
        intentInputTypes: [String] = [],
        remoteResource: HanlinScriptingRemoteResource? = nil,
        unknownFields: [String: HanlinJSONValue] = [:]
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.localizedNames = localizedNames
        self.localizedDescriptions = localizedDescriptions
        self.author = author
        self.contributors = contributors
        self.icon = icon
        self.iconImage = iconImage
        self.color = color
        self.entry = entry
        self.runInApp = runInApp
        self.intentInputTypes = intentInputTypes
        self.remoteResource = remoteResource
        self.unknownFields = unknownFields
    }

    private static let knownKeys: Set<String> = [
        "name", "version", "description", "localizedNames",
        "localizedDescriptions", "author", "contributors", "icon",
        "iconImage", "color", "entry", "runInApp", "intentInputTypes",
        "remoteResource"
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        func key(_ value: String) -> DynamicCodingKey { DynamicCodingKey(value) }
        name = try container.decode(String.self, forKey: key("name"))
        version = try container.decode(String.self, forKey: key("version"))
        description = try container.decodeIfPresent(String.self, forKey: key("description"))
        localizedNames = try container.decodeIfPresent(
            [String: String].self,
            forKey: key("localizedNames")
        ) ?? [:]
        localizedDescriptions = try container.decodeIfPresent(
            [String: String].self,
            forKey: key("localizedDescriptions")
        ) ?? [:]
        author = try container.decodeIfPresent(HanlinScriptingAuthor.self, forKey: key("author"))
        contributors = try container.decodeIfPresent(
            [HanlinScriptingAuthor].self,
            forKey: key("contributors")
        ) ?? []
        icon = try container.decodeIfPresent(String.self, forKey: key("icon"))
        iconImage = try container.decodeIfPresent(String.self, forKey: key("iconImage"))
        color = try container.decodeIfPresent(String.self, forKey: key("color"))
        entry = try container.decodeIfPresent(String.self, forKey: key("entry"))
        runInApp = try container.decodeIfPresent(Bool.self, forKey: key("runInApp")) ?? false
        intentInputTypes = try container.decodeIfPresent(
            [String].self,
            forKey: key("intentInputTypes")
        ) ?? []
        remoteResource = try container.decodeIfPresent(
            HanlinScriptingRemoteResource.self,
            forKey: key("remoteResource")
        )
        var preserved: [String: HanlinJSONValue] = [:]
        for candidate in container.allKeys where !Self.knownKeys.contains(candidate.stringValue) {
            preserved[candidate.stringValue] = try container.decode(
                ManifestJSONValue.self,
                forKey: candidate
            ).value
        }
        unknownFields = preserved
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        func key(_ value: String) -> DynamicCodingKey { DynamicCodingKey(value) }
        try container.encode(name, forKey: key("name"))
        try container.encode(version, forKey: key("version"))
        try container.encodeIfPresent(description, forKey: key("description"))
        try container.encode(localizedNames, forKey: key("localizedNames"))
        try container.encode(localizedDescriptions, forKey: key("localizedDescriptions"))
        try container.encodeIfPresent(author, forKey: key("author"))
        try container.encode(contributors, forKey: key("contributors"))
        try container.encodeIfPresent(icon, forKey: key("icon"))
        try container.encodeIfPresent(iconImage, forKey: key("iconImage"))
        try container.encodeIfPresent(color, forKey: key("color"))
        try container.encodeIfPresent(entry, forKey: key("entry"))
        try container.encode(runInApp, forKey: key("runInApp"))
        try container.encode(intentInputTypes, forKey: key("intentInputTypes"))
        try container.encodeIfPresent(remoteResource, forKey: key("remoteResource"))
        for (field, value) in unknownFields where !Self.knownKeys.contains(field) {
            try container.encode(ManifestJSONValue(value), forKey: key(field))
        }
    }
}

/// Adapts ordinary JSON used by `script.json` to the canonical value model.
/// `HanlinJSONValue.Codable` intentionally uses a tagged wire format, so it
/// cannot be decoded directly from forward-compatible manifest fields.
private struct ManifestJSONValue: Codable {
    let value: HanlinJSONValue

    init(_ value: HanlinJSONValue) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            value = .null
        } else if let decoded = try? single.decode(Bool.self) {
            value = .bool(decoded)
        } else if let decoded = try? single.decode(Int64.self) {
            value = .integer(decoded)
        } else if let decoded = try? single.decode(Double.self) {
            value = try .finiteNumber(decoded)
        } else if let decoded = try? single.decode(String.self) {
            value = .string(decoded)
        } else if let decoded = try? single.decode([ManifestJSONValue].self) {
            value = .array(decoded.map(\.value))
        } else {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            let members = try container.allKeys.map { key in
                (key: key.stringValue, value: try container.decode(Self.self, forKey: key).value)
            }
            value = try .object(HanlinObject(uniqueMembers: members))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch value {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .array(values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(Self(value))
            }
        case let .object(values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values {
                try container.encode(Self(value), forKey: DynamicCodingKey(key))
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}
