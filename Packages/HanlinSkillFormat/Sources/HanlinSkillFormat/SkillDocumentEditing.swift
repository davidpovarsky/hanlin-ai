import Foundation
import Yams

public extension SkillMarkdownDocument {
    /// Edits the three UI fields/body only. Unknown fields, comments, tags and formatting remain
    /// in their original byte spans. Anchored known fields refuse edits that could alter aliases.
    /// A nil title removes its value using YAML null, retaining the key and any inline comment.
    func updating(name: String, title: String?, description: String, instructionBody: String,
                  limits: SkillMarkdownLimits = .default) throws -> SkillMarkdownDocument {
        var edits: [(Range<Int>, Data)] = []
        var additions: [(String, String?)] = []
        let fields: [(String, String?, String?)] = [("name", self.name, name), ("title", self.title, title),
                                                  ("description", self.description, description)]
        for (key, old, new) in fields {
            // Swift String equality folds canonical equivalents; an exact edit must not do so.
            if old.map({ Data($0.utf8) }) == new.map({ Data($0.utf8) }) { continue }
            if root[key] != nil {
                guard !inspection.anchoredFields.contains(key), let range = inspection.scalarFieldRanges[key] else {
                    throw SkillMarkdownError(.unsupportedEdit, "Editing \(key) would require rewriting an anchored or complex YAML construct. Original bytes were retained.")
                }
                var replacement = try Self.scalar(new)
                let previous = originalSource.subdata(in: range)
                // Native literal/folded token spans may include their terminating line breaks.
                // Preserve that separation, including blank lines, before the following field.
                let suffix = previous.reversed().prefix(while: { $0 == 10 || $0 == 13 }).reversed()
                replacement.append(contentsOf: suffix)
                edits.append((range, replacement))
            } else if new != nil { additions.append((key, new)) }
        }
        if !additions.isEmpty {
            if inspection.rootIsFlow {
                let prefix = inspection.flowHasTrailingComma ? " " : ", "
                let pairs = try additions.map { key, value in key + ": " + String(decoding: try Self.scalar(value), as: UTF8.self) }
                let offset = inspection.rootEndOffset
                edits.append((offset..<offset, Data((prefix + pairs.joined(separator: ", ")).utf8)))
            } else {
                var appended = Data()
                let offset = frontmatterRange.upperBound
                if offset > frontmatterRange.lowerBound, ![10, 13].contains(originalSource[offset - 1]) { appended.append(newline) }
                for (key, value) in additions {
                    appended.append(Data((String(repeating: " ", count: inspection.rootIndent) + key + ": ").utf8))
                    appended.append(try Self.scalar(value)); appended.append(newline)
                }
                edits.append((offset..<offset, appended))
            }
        }
        let normalized = instructionBody.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .newlines)
        if !Data(normalized.utf8).elementsEqual(Data(self.instructionBody.utf8)) {
            let newBody = normalized.replacingOccurrences(of: "\n", with: String(decoding: newline, as: UTF8.self))
            // The UI operates on normalized instructions; retain the original leading/trailing
            // body line breaks when replacing its content.
            let bytes = Array(rawBody)
            let leading = bytes.prefix(while: { $0 == 10 || $0 == 13 })
            let trailing = bytes.dropFirst(leading.count).reversed().prefix(while: { $0 == 10 || $0 == 13 }).reversed()
            var replacement = Data(leading)
            if bodyRange.isEmpty, bodyRange.lowerBound > 0,
               ![10, 13].contains(originalSource[bodyRange.lowerBound - 1]) {
                // A valid closing fence can be the last bytes of the imported file. Separate
                // newly added instructions from that fence without rewriting its header.
                replacement.append(newline)
            }
            replacement.append(Data(newBody.utf8)); replacement.append(contentsOf: trailing)
            edits.append((bodyRange, replacement))
        }
        guard !edits.isEmpty else { return self }
        var source = originalSource
        for (range, replacement) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { source.replaceSubrange(range, with: replacement) }
        let result = try SkillDocumentParser.parse(source, limits: limits)
        guard Data(result.name.utf8) == Data(name.utf8), result.title.map({ Data($0.utf8) }) == title.map({ Data($0.utf8) }),
              Data(result.description.utf8) == Data(description.utf8), Data(result.instructionBody.utf8) == Data(normalized.utf8) else {
            throw SkillMarkdownError(.unsupportedEdit, "The YAML construct cannot represent this edit without rewriting other source. Original bytes were retained.")
        }
        return result
    }

    /// Fresh content uses the original upstream emitter, including YAML quoting/escaping.
    static func create(name: String, title: String? = nil, description: String, body: String,
                       limits: SkillMarkdownLimits = .default) throws -> SkillMarkdownDocument {
        var entries: [(Node, Node)] = [(Node("name", .init(.str)), Node(name, .init(.str), .doubleQuoted))]
        if let title, !title.isEmpty { entries.append((Node("title", .init(.str)), Node(title, .init(.str), .doubleQuoted))) }
        entries.append((Node("description", .init(.str)), Node(description, .init(.str), .doubleQuoted)))
        let header = try Yams.serialize(node: Node(entries, .init(.map), .block), width: -1, allowUnicode: true)
        return try SkillDocumentParser.parse(Data(("---\n" + header + "---\n\n" + body).utf8), limits: limits)
    }

    private static func scalar(_ value: String?) throws -> Data {
        guard let value else { return Data("null".utf8) }
        let emitted = try Yams.serialize(node: Node(value, .init(.str), .doubleQuoted), width: -1, allowUnicode: true)
        // Upstream adds the document terminator for a root scalar; use its scalar token only.
        let source = Data(emitted.utf8)
        // The inspector only tracks editable SKILL.md keys; use one such key for this token.
        let inspected = try YAMLSourceInspector.inspect(Data(("name: " + emitted).utf8), globalOffset: 0, limits: .default)
        guard let range = inspected.scalarFieldRanges["name"], range.lowerBound >= 6 else {
            throw SkillMarkdownError(.unsupportedEdit, "Unable to emit a YAML scalar.")
        }
        let offset = range.lowerBound - 6, end = range.upperBound - 6
        return source.subdata(in: offset..<end)
    }
}
