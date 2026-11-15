import Foundation
import Testing
@testable import HanlinSkillFormat

@Suite("Original Yams metadata, bounded parsing and lossless edits")
struct SkillDocumentTests {
    private func document(_ header: String, body: String = "\n# Instructions\n") throws -> SkillMarkdownDocument {
        try SkillDocumentParser.parse("---\n" + header + "\n---\n" + body)
    }
    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "openclaw", withExtension: "md", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    private func expectFailure(_ code: SkillMarkdownError.Code, source: String, limits: SkillMarkdownLimits = .default) {
        #expect(throws: SkillMarkdownError.self) {
            do { _ = try SkillDocumentParser.parse(source, limits: limits) }
            catch let error as SkillMarkdownError { #expect(error.code == code); throw error }
        }
    }

    @Test func openClawNestedMetadataUsesOneTaggedContract() throws {
        let source = try fixture(), parsed = try SkillDocumentParser.parse(source, validation: .strict)
        #expect(parsed.originalSource == source)
        #expect(parsed.description == "Weather: current conditions # and forecasts")
        let claw = try #require(parsed.metadata?["openclaw"])
        #expect(claw["requires"]?["bins"]?.sequence?.map(\.stringValue) == ["curl", "jq"])
        let install = try #require(claw["install"]?.sequence?.first)
        #expect(install["optional"]?.booleanValue == true)
        #expect(install["retries"]?.scalar?.text == "9007199254740993")
        #expect(install["retries"]?.stringValue == nil)
        if case .mapping(let tag, _) = parsed.metadata?["vendor-extra"] { #expect(tag.rawValue == "!vendor") }
        else { Issue.record("Unknown tagged mapping was lost") }
        #expect(parsed.root["unknown-header"] == parsed.root["unknown-copy"])
        #expect(parsed.allowedTools?.sequence?.count == 2)
        #expect(parsed.findings.isEmpty)
    }

    @Test func noOpAndTypedCodableRetainOriginalData() throws {
        let source = try fixture(), parsed = try SkillDocumentParser.parse(source)
        let result = try parsed.updating(name: parsed.name, title: parsed.title, description: parsed.description, instructionBody: parsed.instructionBody)
        #expect(result.originalSource == source)
        let roundtrip = try JSONDecoder().decode(SkillMetadataNode.self, from: JSONEncoder().encode(parsed.root))
        #expect(roundtrip == parsed.root)
    }

    @Test func slicedDataUsesDocumentRelativeRangesWithoutChangingBytes() throws {
        let original = Data("\u{FEFF}---\r\nname: sliced-data\r\ndescription: \"שלום 😀\"\r\nunknown: {retained: true}\r\n---\r\n\r\nInstructions\r\n".utf8)
        let prefixed = Data([0, 1, 2, 3]) + original
        let sliced = prefixed.dropFirst(4)
        #expect(sliced.startIndex == 4)
        let parsed = try SkillDocumentParser.parse(sliced)
        #expect(parsed.originalSource == original)
        #expect(parsed.originalSource.startIndex == 0)
        #expect(parsed.rawBody == Data("\r\nInstructions\r\n".utf8))
        let edited = try parsed.updating(name: parsed.name, title: nil, description: "Edited", instructionBody: parsed.instructionBody)
        #expect(edited.root["unknown"] == parsed.root["unknown"])
        #expect(edited.rawBody == parsed.rawBody)
        #expect(edited.description == "Edited")
    }

    @Test func bomCRLFUnicodeMarksMapToExactUTF8Bytes() throws {
        let raw = "\u{FEFF}---\r\nunknown: \"שלום 👩🏽‍💻 e\u{301}\"\r\nname: unicode-skill\r\ntitle: \"כותרת 😀\" # keep\r\ndescription: \"old # : text\"\r\n---\r\n\r\n# גוף\r\n"
        let parsed = try SkillDocumentParser.parse(raw)
        let range = try #require(parsed.inspection.scalarFieldRanges["title"])
        #expect(parsed.originalSource.subdata(in: range) == Data("\"כותרת 😀\"".utf8))
        let descRange = try #require(parsed.inspection.scalarFieldRanges["description"])
        #expect(parsed.originalSource.subdata(in: descRange) == Data("\"old # : text\"".utf8))
        let edited = try parsed.updating(name: parsed.name, title: "חדש 🧪", description: "yes: # \"quoted\"", instructionBody: parsed.instructionBody)
        #expect(edited.originalSource.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(edited.rawBody == parsed.rawBody)
        #expect(edited.body == "\r\n# גוף\r\n")
        #expect(String(decoding: edited.originalSource, as: UTF8.self).contains("# keep\r\n"))
        #expect(edited.root["unknown"] == parsed.root["unknown"])
        #expect(!String(decoding: edited.originalSource, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    @Test func allKnownEditsPreserveUnknownBytesAndBody() throws {
        let parsed = try SkillDocumentParser.parse(fixture())
        let edited = try parsed.updating(name: "weather-new", title: "תוצאה: # 🧪", description: "first\nsecond\n", instructionBody: parsed.instructionBody)
        let unknownStart = try #require(parsed.rawFrontmatter.range(of: Data("metadata:".utf8)))
        let unknownBytes = parsed.rawFrontmatter.subdata(in: unknownStart.lowerBound..<parsed.rawFrontmatter.count)
        #expect(edited.originalSource.range(of: unknownBytes) != nil)
        #expect(edited.metadata == parsed.metadata)
        #expect(edited.rawBody == parsed.rawBody)
        #expect(edited.title == "תוצאה: # 🧪")
        #expect(edited.description == "first\nsecond\n")
    }

    @Test func bodyOnlyEditPreservesEntireFrontmatterAndNewlineStyle() throws {
        let raw = "---\r\nname: body-test\r\ndescription: Description\r\nunknown: {a: [1, 2]} # retain\r\n---\r\n\r\nold\r\n\r\n"
        let parsed = try SkillDocumentParser.parse(raw)
        let edited = try parsed.updating(name: parsed.name, title: parsed.title, description: parsed.description, instructionBody: "new\nשלום")
        #expect(edited.rawFrontmatter == parsed.rawFrontmatter)
        #expect(edited.rawBody == Data("\r\nnew\r\nשלום\r\n\r\n".utf8))
    }

    @Test(arguments: ["|", "|-", "|+", ">", ">-"])
    func blockScalarUsesNativeSpanAndRetainsFollowingField(style: String) throws {
        let parsed = try document("name: multiline\ndescription: \(style)\n  first\n  ---\n  שלום 😀\n\nunknown: [one, two] # retain")
        #expect(parsed.description.contains("---"))
        let edited = try parsed.updating(name: parsed.name, title: nil, description: "new\nvalue", instructionBody: parsed.instructionBody)
        #expect(edited.root["unknown"] == parsed.root["unknown"])
        #expect(String(decoding: edited.originalSource, as: UTF8.self).contains("unknown: [one, two] # retain"))
        #expect(edited.description == "new\nvalue")
    }

    @Test(arguments: [false, true])
    func flowMappingAddsMissingFieldWithOrWithoutTrailingComma(trailing: Bool) throws {
        let parsed = try document("{name: flow-test, description: old, extra: {a: [1, 2]}\(trailing ? "," : "")}")
        let edited = try parsed.updating(name: parsed.name, title: "added: #title", description: "new", instructionBody: parsed.instructionBody)
        #expect(edited.title == "added: #title")
        #expect(edited.root["extra"] == parsed.root["extra"])
    }

    @Test func scalarAliasCanBeEditedWithoutChangingItsSource() throws {
        let parsed = try document("unknown: &d \"original: # text\"\nname: alias-test\ndescription: *d")
        let edited = try parsed.updating(name: parsed.name, title: nil, description: "replacement", instructionBody: parsed.instructionBody)
        #expect(edited.root["unknown"] == parsed.root["unknown"])
        #expect(edited.description == "replacement")
    }

    @Test func anchoredKnownFieldFailsExplicitlyWithoutChangingSource() throws {
        let parsed = try document("name: anchor-test\ndescription: &desc original\nunknown: *desc")
        #expect(throws: SkillMarkdownError.self) {
            do { _ = try parsed.updating(name: parsed.name, title: nil, description: "new", instructionBody: parsed.instructionBody) }
            catch let error as SkillMarkdownError { #expect(error.code == .unsupportedEdit); throw error }
        }
        #expect(parsed.root["unknown"]?.stringValue == "original")
        let noOp = try parsed.updating(name: parsed.name, title: nil, description: parsed.description, instructionBody: parsed.instructionBody)
        #expect(noOp.originalSource == parsed.originalSource)
    }

    @Test func quotedKeysAndExplicitStringTagsUseOriginalScanner() throws {
        let parsed = try document("\"name\": quoted-test\n'description': !!str 'yes' # remain\nextra: !tag [true, false]")
        let edited = try parsed.updating(name: parsed.name, title: nil, description: "no: # text", instructionBody: parsed.instructionBody)
        #expect(edited.description == "no: # text")
        #expect(String(decoding: edited.originalSource, as: UTF8.self).contains("!!str \"no: # text\" # remain"))
        #expect(edited.root["extra"] == parsed.root["extra"])
    }

    @Test func canonicalUnicodeEditDoesNotCollapseDistinctBytes() throws {
        let parsed = try document("name: unicode-test\ntitle: \"e\u{301}\"\ndescription: Description\nextra: \"e\u{301}\"")
        let edited = try parsed.updating(name: parsed.name, title: "é", description: parsed.description, instructionBody: parsed.instructionBody)
        #expect(edited.title.map { Data($0.utf8) } == Data("é".utf8))
        #expect(edited.root["extra"]?.stringValue.map { Data($0.utf8) } == Data("e\u{301}".utf8))
    }

    @Test func optionalTitleRemovalRetainsInlineComment() throws {
        let parsed = try document("name: remove-title\ntitle: Title # keep\ndescription: Description")
        let edited = try parsed.updating(name: parsed.name, title: nil, description: parsed.description, instructionBody: parsed.instructionBody)
        #expect(edited.title == nil)
        #expect(String(decoding: edited.originalSource, as: UTF8.self).contains("title: null # keep"))
    }

    @Test func newDocumentsUseUpstreamEmitterEscaping() throws {
        let created = try SkillMarkdownDocument.create(name: "emit-test", title: "Title: # 😀", description: "yes: # \"quotes\"\nsecond", body: "# Instructions")
        #expect(created.description == "yes: # \"quotes\"\nsecond")
        #expect(created.title == "Title: # 😀")
        #expect(created.instructionBody == "# Instructions")
    }

    @Test func compatibleMigrationReadsLegacyWithoutRewriting() throws {
        let raw = Data("---\nname: legacy_skill\nunknown: {still: [1, 2]}\n---\nold".utf8)
        let parsed = try SkillDocumentParser.parse(raw)
        #expect(parsed.originalSource == raw)
        #expect(Set(parsed.findings.map(\.code)) == ["legacy-name", "description-length"])
        #expect(throws: SkillMarkdownError.self) { try SkillDocumentParser.parse(raw, validation: .strict) }
    }

    @Test func complexUnknownKeysRemainOrderedTaggedData() throws {
        let parsed = try document("name: complex-test\ndescription: Description\nextra:\n  ? [one, two]\n  : !unknown {nested: true}")
        let entry = try #require(parsed.root["extra"]?.mapping?.first)
        #expect(entry.key.sequence?.count == 2)
        #expect(entry.value["nested"]?.booleanValue == true)
    }

    @Test func malformedDuplicateAndInvalidRootsFailClosed() throws {
        expectFailure(.malformedYAML, source: "---\nname: broken\ndescription: [unclosed\n---\n")
        expectFailure(.malformedYAML, source: "---\nname: duplicate\nname: other\n---\n")
        expectFailure(.invalidField, source: "---\n[one, two]\n---\n")
        expectFailure(.missingRequiredField, source: "---\ndescription: No name\n---\n")
        expectFailure(.missingFrontmatter, source: "No frontmatter")
        expectFailure(.missingFrontmatter, source: "---\nname: missing-close")
        #expect(throws: SkillMarkdownError.self) { try SkillDocumentParser.parse(Data([0xFF, 0xFE])) }
    }

    @Test func sourceAndConfigurationBudgetsFailBeforeComposition() {
        let raw = "---\nname: budget-test\ndescription: Description\n---\n"
        expectFailure(.inputLimit, source: raw, limits: .init(maximumSourceBytes: 5))
        expectFailure(.inputLimit, source: raw, limits: .init(maximumFrontmatterBytes: 5))
        expectFailure(.inputLimit, source: raw, limits: .init(maximumNodes: Int.max))
        expectFailure(.nodeLimit, source: raw, limits: .init(maximumNodes: 2))
    }

    @Test func physicalAndAliasExpandedDepthAreBounded() {
        expectFailure(.nestingLimit, source: "---\nname: depth-test\ndescription: Description\nextra: [[[[[0]]]]]\n---\n", limits: .init(maximumDepth: 4))
        expectFailure(.nestingLimit, source: "---\nname: depth-test\ndescription: Description\na: &a [0]\nb: &b [*a]\nc: &c [*b]\nd: [*c]\n---\n", limits: .init(maximumDepth: 4))
    }

    @Test func aliasesCyclesAndTextExpansionHaveSeparateResourceErrors() {
        expectFailure(.aliasLimit, source: "---\nname: cycle-test\ndescription: Description\na: &a [*a]\n---\n")
        expectFailure(.malformedYAML, source: "---\nname: missing-alias\ndescription: *missing\n---\n")
        expectFailure(.aliasLimit, source: "---\nname: alias-budget\ndescription: Description\na: &a value\nb: [*a, *a]\n---\n", limits: .init(maximumAliases: 1))
        let expanded = "---\nname: alias-budget\ndescription: Description\na: &a [1, 2, 3, 4]\nb: [*a, *a, *a, *a]\n---\n"
        expectFailure(.expansionLimit, source: expanded, limits: .init(maximumExpandedNodes: 20))
        let text = "---\nname: text-budget\ndescription: Description\na: &a \"" + String(repeating: "x", count: 1000) + "\"\nb: [*a, *a, *a]\n---\n"
        expectFailure(.expansionLimit, source: text, limits: .init(maximumExpandedScalarBytes: 2500))
    }

    @Test func parsingHonorsCancellation() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SkillDocumentParser.parse("---\nname: cancelled\ndescription: Description\n---\n")
        }
        do { _ = try await task.value; Issue.record("Cancelled parse succeeded") }
        catch let error as SkillMarkdownError { #expect(error.code == .cancelled) }
        catch { Issue.record("Wrong cancellation error: \(error)") }
    }
}
