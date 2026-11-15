import Foundation
import Yams

public enum SkillDocumentParser {
    public enum Validation: Sendable { case compatible, strict }

    /// Compatible reads retain installed legacy identifiers; standards violations remain findings.
    /// Neither mode interprets metadata as permissions, readiness or executable configuration.
    public static func parse(_ source: Data, limits: SkillMarkdownLimits = .default,
                             validation: Validation = .compatible) throws -> SkillMarkdownDocument {
        try checkCancellation()
        try validate(limits)
        guard source.count <= limits.maximumSourceBytes else { throw SkillMarkdownError(.inputLimit, "SKILL.md exceeds its byte budget.") }
        guard String(data: source, encoding: .utf8) != nil else { throw SkillMarkdownError(.invalidUTF8, "SKILL.md must be UTF-8.") }
        let envelope = try envelope(source)
        guard envelope.header.count <= limits.maximumFrontmatterBytes else { throw SkillMarkdownError(.inputLimit, "YAML frontmatter exceeds its byte budget.") }
        let data = source.subdata(in: envelope.header)
        let inspection: YAMLSourceInspection
        do { inspection = try YAMLSourceInspector.inspect(data, globalOffset: envelope.header.lowerBound, limits: limits) }
        catch is CancellationError { throw SkillMarkdownError(.cancelled, "Skill parsing was cancelled.") }
        try checkCancellation()
        let original: Node
        do {
            guard let node = try Yams.compose(yaml: String(decoding: data, as: UTF8.self), .default, .default, .utf8) else {
                throw SkillMarkdownError(.missingRequiredField, "Frontmatter requires a name.")
            }
            original = node
        } catch let error as SkillMarkdownError { throw error }
        catch {
            // Do not embed Yams' source snippet in diagnostics (metadata can contain secrets).
            throw SkillMarkdownError(.malformedYAML, "Yams could not compose the frontmatter; duplicate or unsupported keys may be present.")
        }
        let root = try project(original)
        guard root.mapping != nil else { throw SkillMarkdownError(.invalidField, "Frontmatter must be a YAML mapping.") }
        var findings: [SkillMetadataFinding] = []
        func string(_ key: String, required: Bool) throws -> String? {
            guard let node = root[key] else {
                if required { throw SkillMarkdownError(.missingRequiredField, "Frontmatter requires \(key).") }
                return nil
            }
            guard let scalar = node.scalar else { throw SkillMarkdownError(.invalidField, "\(key) must be a scalar string.") }
            if scalar.tag.rawValue == "tag:yaml.org,2002:null", !required { return nil }
            if scalar.stringValue == nil {
                findings.append(.init("non-string-\(key)", severity: .error, "\(key) should be a quoted YAML string."))
            }
            return scalar.text
        }
        guard let name = try string("name", required: true), !name.isEmpty else {
            throw SkillMarkdownError(.missingRequiredField, "Frontmatter requires a nonempty name.")
        }
        let description = try string("description", required: false) ?? ""
        let title = try string("title", required: false)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validName = !name.isEmpty && name.utf8.count <= 64 && name.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            && !name.hasPrefix("-") && !name.hasSuffix("-") && !name.contains("--")
        if !validName { findings.append(.init("legacy-name", severity: .error, "Standard skill names use 1–64 lowercase ASCII letters, digits and single hyphens.")) }
        if description.isEmpty || description.unicodeScalars.count > 1024 {
            findings.append(.init("description-length", severity: .error, "Standard descriptions contain 1–1024 Unicode scalar values."))
        }
        if let compatibility = root["compatibility"], compatibility.stringValue == nil || (compatibility.stringValue?.unicodeScalars.count ?? 0) > 500 {
            findings.append(.init("compatibility-type", severity: .error, "Compatibility should be a string of at most 500 Unicode scalar values."))
        }
        if validation == .strict, let finding = findings.first(where: { $0.severity == .error }) {
            throw SkillMarkdownError(.invalidField, finding.message)
        }
        try checkCancellation()
        return .init(originalSource: source, frontmatterRange: envelope.header, bodyRange: envelope.body,
                     root: root, name: name, title: title?.isEmpty == false ? title : nil,
                     description: description, findings: findings, inspection: inspection,
                     newline: envelope.newline, openingIndent: envelope.indent)
    }

    public static func parse(_ source: String, limits: SkillMarkdownLimits = .default,
                             validation: Validation = .compatible) throws -> SkillMarkdownDocument {
        try parse(Data(source.utf8), limits: limits, validation: validation)
    }

    private static func project(_ node: Node) throws -> SkillMetadataNode {
        try checkCancellation()
        let tag = SkillYAMLTag(rawValue: node.tag.description)
        switch node {
        case .scalar(let scalar):
            return .scalar(.init(text: scalar.string, tag: tag.rawValue,
                                 booleanValue: tag.rawValue == "tag:yaml.org,2002:bool" ? node.bool : nil))
        case .mapping(let mapping):
            return .mapping(tag: tag, entries: try mapping.map { .init(key: try project($0.key), value: try project($0.value)) })
        case .sequence(let sequence):
            return .sequence(tag: tag, values: try sequence.map(project))
        case .alias:
            throw SkillMarkdownError(.malformedYAML, "Yams returned an unresolved alias.")
        }
    }

    private static func checkCancellation() throws {
        if Task.isCancelled { throw SkillMarkdownError(.cancelled, "Skill parsing was cancelled.") }
    }

    private static func validate(_ limits: SkillMarkdownLimits) throws {
        guard (1...67_108_864).contains(limits.maximumSourceBytes),
              (1...4_194_304).contains(limits.maximumFrontmatterBytes),
              (1...128).contains(limits.maximumDepth), (1...131_072).contains(limits.maximumNodes),
              (1...262_144).contains(limits.maximumExpandedNodes), (0...2_048).contains(limits.maximumAliases),
              (1...67_108_864).contains(limits.maximumExpandedScalarBytes) else {
            throw SkillMarkdownError(.inputLimit, "Invalid or excessive parser budgets.")
        }
    }

    private struct Envelope {
        let header: Range<Int>
        let body: Range<Int>
        let newline: Data
        let indent: Int
    }

    /// Markdown fence boundaries only. YAML syntax/indentation inside is entirely upstream's.
    private static func envelope(_ source: Data) throws -> Envelope {
        let bytes = [UInt8](source)
        func line(_ start: Int) -> (content: Range<Int>, next: Int) {
            var end = start
            while end < bytes.count, bytes[end] != 10, bytes[end] != 13 { end += 1 }
            var next = end
            if next < bytes.count {
                next += 1
                if bytes[end] == 13, next < bytes.count, bytes[next] == 10 { next += 1 }
            }
            return (start..<end, next)
        }
        let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        let opening = line(start)
        let first = Array(bytes[opening.content])
        let trimmed = first.drop(while: { $0 == 32 || $0 == 9 }).reversed().drop(while: { $0 == 32 || $0 == 9 }).reversed()
        guard Array(trimmed) == [45, 45, 45], opening.next > opening.content.upperBound else {
            throw SkillMarkdownError(.missingFrontmatter, "SKILL.md requires opening and closing --- fences.")
        }
        let indent = first.prefix(while: { $0 == 32 }).count
        let newline = source.subdata(in: opening.content.upperBound..<opening.next)
        var cursor = opening.next
        while cursor < bytes.count {
            let current = line(cursor)
            let content = bytes[current.content]
            // A literal block may contain indented '---'; only a column-zero fence closes it.
            if content.starts(with: [45, 45, 45]), content.dropFirst(3).allSatisfy({ $0 == 32 || $0 == 9 }) {
                return .init(header: opening.next..<cursor, body: current.next..<bytes.count, newline: newline, indent: indent)
            }
            cursor = current.next
        }
        throw SkillMarkdownError(.missingFrontmatter, "SKILL.md requires a closing --- fence.")
    }
}
