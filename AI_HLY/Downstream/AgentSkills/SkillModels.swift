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
        public let description: String
        public let body: String
        public let rawFrontmatter: [String: String]
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
        let lines = content.components(separatedBy: .newlines)
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
        for i in 1..<closeIdx {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colonIdx = line.firstIndex(of: ":") else {
                continue
            }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            frontmatter[key] = value
        }

        guard let name = frontmatter["name"], !name.isEmpty else {
            throw ParseError.missingRequiredField("name")
        }
        guard let desc = frontmatter["description"], !desc.isEmpty else {
            throw ParseError.missingRequiredField("description")
        }

        let bodyStartIndex = closeIdx + 1
        let body: String
        if bodyStartIndex < lines.count {
            body = lines[bodyStartIndex...].joined(separator: "\n").trimmingCharacters(in: .newlines)
        } else {
            body = ""
        }

        return ParsedSkillMarkdown(
            name: name,
            description: desc,
            body: body,
            rawFrontmatter: frontmatter
        )
    }

    public static func serialize(name: String, description: String, body: String) -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)
        """
    }
}
