import Foundation

/// Immutable metadata data only. It cannot grant tools, install packages or execute a script.
public struct SkillYAMLTag: RawRepresentable, Codable, Hashable, Sendable {
    private let utf8: Data
    public init(rawValue: String) { utf8 = Data(rawValue.utf8) }
    public var rawValue: String { String(decoding: utf8, as: UTF8.self) }
}

public struct SkillYAMLScalar: Codable, Hashable, Sendable {
    private let utf8: Data
    public let tag: SkillYAMLTag
    public let booleanValue: Bool?
    public var text: String { String(decoding: utf8, as: UTF8.self) }
    public var stringValue: String? { tag.rawValue == "tag:yaml.org,2002:str" ? text : nil }
    init(text: String, tag: String, booleanValue: Bool?) {
        utf8 = Data(text.utf8); self.tag = .init(rawValue: tag); self.booleanValue = booleanValue
    }
}

public struct SkillYAMLMappingEntry: Codable, Hashable, Sendable {
    public let key: SkillMetadataNode
    public let value: SkillMetadataNode
    init(key: SkillMetadataNode, value: SkillMetadataNode) { self.key = key; self.value = value }
}

/// One ordered tagged representation shared by OpenClaw/Runtime/AST consumers. Numbers keep
/// their scalar text, unknown tags/complex keys remain data, and exact Unicode is never folded.
public indirect enum SkillMetadataNode: Codable, Hashable, Sendable {
    case scalar(SkillYAMLScalar)
    case sequence(tag: SkillYAMLTag, values: [SkillMetadataNode])
    case mapping(tag: SkillYAMLTag, entries: [SkillYAMLMappingEntry])

    public var scalar: SkillYAMLScalar? { if case .scalar(let value) = self { return value }; return nil }
    public var stringValue: String? { scalar?.stringValue }
    public var booleanValue: Bool? { scalar?.booleanValue }
    public var sequence: [SkillMetadataNode]? { if case .sequence(_, let value) = self { return value }; return nil }
    public var mapping: [SkillYAMLMappingEntry]? { if case .mapping(_, let value) = self { return value }; return nil }
    /// Ambiguous/multiple keys return nil; no hidden last-key-wins flattening.
    public subscript(_ key: String) -> SkillMetadataNode? {
        guard let mapping else { return nil }
        let matches = mapping.filter { $0.key.stringValue?.utf8.elementsEqual(key.utf8) == true }
        return matches.count == 1 ? matches[0].value : nil
    }
}

public struct SkillSourcePosition: Codable, Hashable, Sendable {
    public let line: Int
    public let column: Int
    public let byteOffset: Int
    public init(line: Int, column: Int, byteOffset: Int) { self.line = line; self.column = column; self.byteOffset = byteOffset }
}

public struct SkillMetadataFinding: Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Hashable, Sendable { case warning, error }
    public let code: String
    public let severity: Severity
    public let message: String
    public let position: SkillSourcePosition?
    init(_ code: String, severity: Severity = .warning, _ message: String, position: SkillSourcePosition? = nil) {
        self.code = code; self.severity = severity; self.message = message; self.position = position
    }
}

public struct SkillMarkdownError: Error, LocalizedError, Hashable, Sendable {
    public enum Code: String, Codable, Hashable, Sendable {
        case invalidUTF8, missingFrontmatter, malformedYAML, missingRequiredField, invalidField
        case inputLimit, nestingLimit, nodeLimit, aliasLimit, expansionLimit, unsupportedEdit, cancelled
    }
    public let code: Code
    public let message: String
    public let position: SkillSourcePosition?
    public var errorDescription: String? {
        if let position { return "\(message) (line \(position.line), column \(position.column))" }
        return message
    }
    init(_ code: Code, _ message: String, position: SkillSourcePosition? = nil) {
        self.code = code; self.message = message; self.position = position
    }
}

public struct SkillMarkdownLimits: Hashable, Sendable {
    public var maximumSourceBytes: Int
    public var maximumFrontmatterBytes: Int
    public var maximumDepth: Int
    public var maximumNodes: Int
    public var maximumExpandedNodes: Int
    public var maximumAliases: Int
    public var maximumExpandedScalarBytes: Int
    public init(maximumSourceBytes: Int = 16 * 1_048_576, maximumFrontmatterBytes: Int = 1_048_576,
                maximumDepth: Int = 64, maximumNodes: Int = 32_768, maximumExpandedNodes: Int = 65_536,
                maximumAliases: Int = 512, maximumExpandedScalarBytes: Int = 8 * 1_048_576) {
        self.maximumSourceBytes = maximumSourceBytes; self.maximumFrontmatterBytes = maximumFrontmatterBytes
        self.maximumDepth = maximumDepth; self.maximumNodes = maximumNodes
        self.maximumExpandedNodes = maximumExpandedNodes; self.maximumAliases = maximumAliases
        self.maximumExpandedScalarBytes = maximumExpandedScalarBytes
    }
    public static let `default` = Self()
}

/// Freshly derived from existing SKILL.md bytes; not an additional persisted manifest/store.
/// Read/roundtrip retains all bytes. Known-field/body edits are explicit and preserve other source.
public struct SkillMarkdownDocument: Hashable, Sendable {
    public let originalSource: Data
    public let frontmatterRange: Range<Int>
    public let bodyRange: Range<Int>
    public let root: SkillMetadataNode
    public let name: String
    public let title: String?
    public let description: String
    public let findings: [SkillMetadataFinding]
    public var rawFrontmatter: Data { originalSource.subdata(in: frontmatterRange) }
    public var rawBody: Data { originalSource.subdata(in: bodyRange) }
    public var body: String { String(decoding: rawBody, as: UTF8.self) }
    public var instructionBody: String { body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .newlines) }
    public var metadata: SkillMetadataNode? { root["metadata"] }
    public var compatibility: String? { root["compatibility"]?.stringValue }
    public var allowedTools: SkillMetadataNode? { root["allowed-tools"] }
    public var displayTitle: String { title?.isEmpty == false ? title! : name }

    /// Legacy scalar-only projection, never the authoritative complete metadata representation.
    public var legacyStringFrontmatter: [String: String] {
        var result: [String: String] = [:]
        for entry in root.mapping ?? [] {
            if let key = entry.key.stringValue, let scalar = entry.value.scalar { result[key] = scalar.text }
        }
        return result
    }

    let inspection: YAMLSourceInspection
    let newline: Data
    let openingIndent: Int
}
