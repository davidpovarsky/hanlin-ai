import Foundation
import HanlinSkillFormat

/// Yams remains the only YAML parser. JSON is just the unchanged upstream API's wire format.
enum SkillOpenClawProjection {
    static let probeSHA256 = "b1f021007db883226b65d3d5b70f83e009f00a259fc715e464ca2c7c8dfc73ec"

    struct Input: Encodable {
        let scope = "native"
        let source = "hanlin-native"
        let name: String
        let enabled: Bool
        let metadataPresence: String
        let frontmatter: [String: String]
        let bins: [String: Bool]
        let configFacts: [String: Bool] = [:]
    }

    static func input(_ document: SkillMarkdownDocument, enabled: Bool, bins: [String: Bool]) throws -> Input {
        let presence: String
        if let metadata = document.metadata {
            if metadata.stringValue != nil { presence = "present" }
            else if metadata.mapping != nil {
                presence = metadata["openclaw"] != nil ? "present" : metadata["clawdbot"] != nil ? "unsupported" : "absent"
            } else { presence = "unsupported" }
        } else { presence = "absent" }
        return .init(name: document.name, enabled: enabled, metadataPresence: presence,
                     frontmatter: try frontmatter(document), bins: bins)
    }

    static func invocationFrontmatter(_ document: SkillMarkdownDocument) throws -> [String: String] {
        guard document.findings.isEmpty else { throw RuntimeCoreError.invalidDependencyManifest }
        var values = ["name": document.name]
        for key in ["user-invocable", "disable-model-invocation"] {
            if let node = document.root[key] {
                guard let scalar = node.scalar,
                      ["tag:yaml.org,2002:str", "tag:yaml.org,2002:bool"].contains(scalar.tag.rawValue) else {
                    throw RuntimeCoreError.invalidDependencyManifest
                }
                values[key] = scalar.booleanValue.map { $0 ? "true" : "false" } ?? scalar.text
            }
        }
        return values
    }

    static func frontmatter(_ document: SkillMarkdownDocument) throws -> [String: String] {
        var values = try invocationFrontmatter(document)
        if let metadata = document.metadata {
            values["metadata"] = try metadata.stringValue ?? String(decoding: json(metadata), as: UTF8.self)
        }
        return values
    }

    /// Emit ordered keys directly. Swift Dictionary equality must not fold distinct
    /// Unicode spellings or hide duplicate/complex Yams keys on this boundary.
    private static func json(_ node: SkillMetadataNode) throws -> Data {
        switch node {
        case .scalar(let scalar):
            if let value = scalar.stringValue { return try JSONEncoder().encode(value) }
            if let value = scalar.booleanValue { return Data((value ? "true" : "false").utf8) }
            if scalar.tag.rawValue == "tag:yaml.org,2002:null" { return Data("null".utf8) }
            if scalar.tag.rawValue == "tag:yaml.org,2002:int",
               let value = Int64(scalar.text), (-9_007_199_254_740_991...9_007_199_254_740_991).contains(value) {
                return try JSONEncoder().encode(value)
            }
            if scalar.tag.rawValue == "tag:yaml.org,2002:float", let value = Double(scalar.text), value.isFinite {
                return try JSONEncoder().encode(value)
            }
        case .sequence(let tag, let values):
            guard tag.rawValue == "tag:yaml.org,2002:seq" else { throw RuntimeCoreError.invalidDependencyManifest }
            return try joined(values.map(json), opening: "[", closing: "]")
        case .mapping(let tag, let entries):
            guard tag.rawValue == "tag:yaml.org,2002:map" else { throw RuntimeCoreError.invalidDependencyManifest }
            var keys = Set<Data>()
            var fields: [Data] = []
            for entry in entries {
                guard let key = entry.key.stringValue, keys.insert(Data(key.utf8)).inserted else {
                    throw RuntimeCoreError.invalidDependencyManifest
                }
                var field = try JSONEncoder().encode(key)
                field.append(contentsOf: ":".utf8)
                field.append(try json(entry.value))
                fields.append(field)
            }
            return joined(fields, opening: "{", closing: "}")
        }
        throw RuntimeCoreError.invalidDependencyManifest
    }

    private static func joined(_ fields: [Data], opening: String, closing: String) -> Data {
        var result = Data(opening.utf8)
        for (index, field) in fields.enumerated() {
            if index > 0 { result.append(contentsOf: ",".utf8) }
            result.append(field)
        }
        result.append(contentsOf: closing.utf8)
        return result
    }
}
