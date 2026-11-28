import Foundation

/// Portable source-level probe using the exact upstream validator snapshot, not a renderer.
@main
struct FixtureIdentifierProbe {
    struct Entry: Codable {
        let fixture: String
        let line: Int
        let field: String
        let identifier: String
    }

    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AI_HLYTests/A2UIFixtures")
        var invalid: [Entry] = []
        var inspected = 0
        for fixture in ["form", "rtl", "update"] {
            let text = try String(contentsOf: root.appendingPathComponent("\(fixture).jsonl"), encoding: .utf8)
            for (index, line) in text.split(whereSeparator: \.isNewline).enumerated() {
                let message = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                let update = message?["updateComponents"] as? [String: Any]
                for component in update?["components"] as? [[String: Any]] ?? [] {
                    var fields = [String: String]()
                    for key in ["id", "child"] {
                        if let value = component[key] as? String { fields[key] = value }
                    }
                    for (childIndex, child) in (component["children"] as? [String] ?? []).enumerated() {
                        fields["children[\(childIndex)]"] = child
                    }
                    for (field, identifier) in fields.sorted(by: { $0.key < $1.key }) {
                        inspected += 1
                        if !UnicodeIdentifierValidator.isValidIdentifier(identifier) {
                            invalid.append(Entry(fixture: fixture, line: index + 1, field: field, identifier: identifier))
                        }
                    }
                }
            }
        }
        struct Result: Encodable {
            let upstreamRevision = "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"
            let scope = "Portable exact-source UAX31 probe; not full SDK validation"
            let originalIdentifierAccepted: Bool
            let correctedIdentifierAccepted: Bool
            let inspectedEntries: Int
            let invalidEntries: [Entry]
        }
        let result = Result(
            originalIdentifierAccepted: UnicodeIdentifierValidator.isValidIdentifier("submit-label"),
            correctedIdentifierAccepted: UnicodeIdentifierValidator.isValidIdentifier("submitLabel"),
            inspectedEntries: inspected, invalidEntries: invalid
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(result))
        FileHandle.standardOutput.write(Data([10]))
    }
}
