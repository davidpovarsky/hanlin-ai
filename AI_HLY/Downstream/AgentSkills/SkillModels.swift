import Foundation
import HanlinPlatformContracts

/// Represents the origin source of a Skill in Hanlin.
public enum SkillSourceKind: String, Codable, Hashable, Sendable {
    case builtin
    case appPackage
    case custom
    case imported
}

/// Metadata stored in `hanlin.json` within a Skill directory.
public struct HanlinSkillMetadata: Codable, Hashable, Sendable {
    public var preferredToolIDs: [String]
    public var triggerHints: [String]
    public var keywords: [String]
    public var baseSkillID: String?
    public var originURL: String?
    public var sha256: String?
    public var isEnabled: Bool
    public var installedAt: Date
    public var updatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case preferredToolIDs
        case triggerHints
        case keywords
        case baseSkillID
        case originURL
        case sha256
        case isEnabled
        case installedAt
        case updatedAt
    }

    public init(
        preferredToolIDs: [String] = [],
        triggerHints: [String] = [],
        keywords: [String] = [],
        baseSkillID: String? = nil,
        originURL: String? = nil,
        sha256: String? = nil,
        isEnabled: Bool = true,
        installedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.preferredToolIDs = preferredToolIDs
        self.triggerHints = triggerHints
        self.keywords = keywords
        self.baseSkillID = baseSkillID
        self.originURL = originURL
        self.sha256 = sha256
        self.isEnabled = isEnabled
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preferredToolIDs = (try? container.decodeIfPresent([String].self, forKey: .preferredToolIDs)) ?? []
        self.triggerHints = (try? container.decodeIfPresent([String].self, forKey: .triggerHints)) ?? []
        self.keywords = (try? container.decodeIfPresent([String].self, forKey: .keywords)) ?? []
        self.baseSkillID = try? container.decodeIfPresent(String.self, forKey: .baseSkillID)
        self.originURL = try? container.decodeIfPresent(String.self, forKey: .originURL)
        self.sha256 = try? container.decodeIfPresent(String.self, forKey: .sha256)
        self.isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        self.installedAt = Self.decodeFlexibleDate(from: container, key: .installedAt) ?? Date()
        self.updatedAt = Self.decodeFlexibleDate(from: container, key: .updatedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferredToolIDs, forKey: .preferredToolIDs)
        try container.encode(triggerHints, forKey: .triggerHints)
        try container.encode(keywords, forKey: .keywords)
        try container.encodeIfPresent(baseSkillID, forKey: .baseSkillID)
        try container.encodeIfPresent(originURL, forKey: .originURL)
        try container.encodeIfPresent(sha256, forKey: .sha256)
        try container.encode(isEnabled, forKey: .isEnabled)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: installedAt), forKey: .installedAt)
        try container.encode(formatter.string(from: updatedAt), forKey: .updatedAt)
    }

    public static func decodeFlexibleDate(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
        if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: str) { return d }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            if let d = f2.date(from: str) { return d }
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if let d = df.date(from: str) { return d }
        }
        if let dbl = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSinceReferenceDate: dbl)
        }
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        return nil
    }

    public static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = f1.date(from: s) { return d }
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                if let d = f2.date(from: s) { return d }
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let d = df.date(from: s) { return d }
            }
            if let dbl = try? c.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: dbl)
            }
            return Date()
        }
        return dec
    }

    public static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

/// Summary record of a resource file bundled inside a Skill.
public struct SkillResourceFile: Codable, Hashable, Identifiable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let byteCount: Int64
    public let isBinary: Bool
    public let mimeType: String

    public init(relativePath: String, byteCount: Int64, isBinary: Bool, mimeType: String) {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.isBinary = isBinary
        self.mimeType = mimeType
    }
}

/// A stored Skill record in the local Skill store.
public struct StoredSkillRecord: Identifiable, Sendable {
    public var id: HanlinSkillID { descriptor.id }
    public let descriptor: HanlinSkillDescriptor
    public let sourceKind: SkillSourceKind
    public let sourcePackageID: String?
    public var isEnabled: Bool
    public var isOverride: Bool
    public var baseSkillID: String?
    public var originURL: String?
    public var sha256: String?
    public var directoryURL: URL?
    public var resources: [SkillResourceFile]
    public var installedAt: Date
    public var updatedAt: Date

    public init(
        descriptor: HanlinSkillDescriptor,
        sourceKind: SkillSourceKind,
        sourcePackageID: String? = nil,
        isEnabled: Bool = true,
        isOverride: Bool = false,
        baseSkillID: String? = nil,
        originURL: String? = nil,
        sha256: String? = nil,
        directoryURL: URL? = nil,
        resources: [SkillResourceFile] = [],
        installedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.descriptor = descriptor
        self.sourceKind = sourceKind
        self.sourcePackageID = sourcePackageID
        self.isEnabled = isEnabled
        self.isOverride = isOverride
        self.baseSkillID = baseSkillID
        self.originURL = originURL
        self.sha256 = sha256
        self.directoryURL = directoryURL
        self.resources = resources
        self.installedAt = installedAt
        self.updatedAt = updatedAt
    }
}

/// Safe parser for standard `SKILL.md` frontmatter and markdown body.
public enum SkillMarkdownParser {
    public struct ParsedSkillMarkdown: Sendable {
        public let name: String
        public let title: String?
        public let description: String
        public let body: String
        public let rawFrontmatter: [String: String]

        public var displayTitle: String {
            if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return name
        }

        public init(
            name: String,
            title: String? = nil,
            description: String,
            body: String,
            rawFrontmatter: [String: String]
        ) {
            self.name = name
            self.title = title
            self.description = description
            self.body = body
            self.rawFrontmatter = rawFrontmatter
        }
    }

    public enum ParseError: Error, LocalizedError, Hashable, Sendable {
        case missingFrontmatter
        case missingRequiredField(String)
        case malformedFrontmatter(String)

        public var errorDescription: String? {
            switch self {
            case .missingFrontmatter:
                return "SKILL.md is missing required YAML frontmatter delimited by '---'."
            case .missingRequiredField(let field):
                return "SKILL.md frontmatter is missing required field: '\(field)'."
            case .malformedFrontmatter(let detail):
                return "SKILL.md frontmatter is malformed: \(detail)"
            }
        }
    }

    public static func parse(_ content: String) throws -> ParsedSkillMarkdown {
        var cleanContent = content
        if cleanContent.hasPrefix("\u{FEFF}") {
            cleanContent.removeFirst()
        }
        cleanContent = cleanContent.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = cleanContent.components(separatedBy: "\n")
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
              firstLine == "---" else {
            throw ParseError.missingFrontmatter
        }

        var closingIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let closeIdx = closingIndex else {
            throw ParseError.missingFrontmatter
        }

        var frontmatter: [String: String] = [:]
        var currentKey: String?
        var multilineMode: Character?
        var multilineBuffer: [String] = []

        func flushMultiline() {
            guard let key = currentKey else { return }
            if multilineMode == ">" {
                frontmatter[key] = multilineBuffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            } else if multilineMode == "|" {
                frontmatter[key] = multilineBuffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            }
            multilineMode = nil
            multilineBuffer = []
            currentKey = nil
        }

        for i in 1..<closeIdx {
            let rawLine = lines[i]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if rawLine.hasPrefix("  ") || rawLine.hasPrefix("\t") {
                if multilineMode != nil {
                    multilineBuffer.append(trimmed)
                    continue
                }
            } else {
                flushMultiline()
            }

            guard let colonIdx = trimmed.firstIndex(of: ":") else {
                continue
            }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            if value == ">" || value == "|" {
                currentKey = key
                multilineMode = value.first
                multilineBuffer = []
                continue
            }

            if (value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2) ||
               (value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2) {
                value = String(value.dropFirst().dropLast())
            }
            frontmatter[key] = value
        }
        flushMultiline()

        guard let name = frontmatter["name"], !name.isEmpty else {
            throw ParseError.missingRequiredField("name")
        }
        let rawTitle = frontmatter["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (rawTitle?.isEmpty == false) ? rawTitle : nil
        let desc = frontmatter["description"] ?? ""

        let bodyStartIndex = closeIdx + 1
        let body: String
        if bodyStartIndex < lines.count {
            body = lines[bodyStartIndex...].joined(separator: "\n").trimmingCharacters(in: .newlines)
        } else {
            body = ""
        }

        return ParsedSkillMarkdown(
            name: name,
            title: title,
            description: desc,
            body: body,
            rawFrontmatter: frontmatter
        )
    }

    public static func serialize(name: String, title: String? = nil, description: String, body: String) -> String {
        var header = "---\nname: \(name)\n"
        if let title = title, !title.isEmpty, title != name {
            header += "title: \(title)\n"
        }
        header += "description: \(description)\n---\n\n\(body)"
        return header
    }
}
