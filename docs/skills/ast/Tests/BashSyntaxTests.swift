import Foundation
import XCTest
@testable import HanlinSkillAnalysisProof

@MainActor
final class BashSyntaxTests: XCTestCase {
    private struct Fixture: Decodable {
        let file: String, source: String
        let commands: [String], references: [String]
        let unknown: Bool
        let conditional: String?, absent: String?, module: String?
    }

    func testTwentyOriginalGrammarFixtures() async throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "bash", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        XCTAssertEqual(fixtures.count, 20)
        let scanner = BashSkillSyntaxAnalyzer()
        for fixture in fixtures {
            let bytes = Data(fixture.source.utf8)
            let report = await scanner.scan(file: fixture.file, utf8: bytes)
            XCTAssertEqual(report.provenance.languageABI, 15, fixture.file)
            XCTAssertNotNil(report.sourceSHA256, fixture.file)
            let commands = Set(report.findings.filter { $0.kind == .command }.compactMap(\.value))
            XCTAssertTrue(Set(fixture.commands).isSubset(of: commands), "\(fixture.file): \(report.findings)")
            let references = Set(report.findings.filter { $0.kind == .scriptReference }.compactMap(\.value))
            XCTAssertEqual(Set(fixture.references), references, fixture.file)
            XCTAssertEqual(report.findings.contains { $0.kind == .unknown }, fixture.unknown, fixture.file)
            if let expected = fixture.conditional {
                XCTAssertTrue(report.findings.contains { $0.value == expected && $0.confidence == .conditionalSyntax }, fixture.file)
            }
            if let absent = fixture.absent { XCTAssertFalse(commands.contains(absent), fixture.file) }
            if let module = fixture.module {
                XCTAssertTrue(report.findings.contains { $0.kind == .moduleReference && $0.value == module
                    && $0.reason == "literalModuleNotDistributionMapping" })
            }
            for finding in report.findings {
                XCTAssertEqual(finding.source.file, fixture.file)
                XCTAssertGreaterThanOrEqual(finding.source.line, 1)
                XCTAssertGreaterThanOrEqual(finding.source.utf8Column, 1)
                XCTAssertLessThanOrEqual(finding.source.byteOffset + finding.source.byteLength, bytes.count)
            }
        }
    }

    func testUTF8LocationsDoNotUseUTF16Offsets() async throws {
        let source = "printf 'שלום🙂'; curl --version\n"
        let bytes = Data(source.utf8)
        let report = await BashSkillSyntaxAnalyzer().scan(file: "עברית.sh", utf8: bytes)
        let curl = try XCTUnwrap(report.findings.first { $0.kind == .command && $0.value == "curl" })
        let offset = try XCTUnwrap(bytes.range(of: Data("curl".utf8))).lowerBound
        XCTAssertEqual(curl.source.byteOffset, offset)
        XCTAssertEqual(curl.source.utf8Column, offset + 1)
        XCTAssertEqual(curl.source.line, 1)
        XCTAssertEqual(curl.source.byteLength, 4)
    }

    func testSourceReferenceCannotReadOrExecuteImportableFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("must-not-exist")
        let script = directory.appendingPathComponent("importable.sh")
        try Data("touch '\(marker.path)'\n".utf8).write(to: script)
        let source = ". '\(script.path)'\n"
        let report = await BashSkillSyntaxAnalyzer().scan(file: "caller.sh", utf8: Data(source.utf8))
        XCTAssertTrue(report.findings.contains { $0.kind == .scriptReference && $0.value == script.path })
        XCTAssertFalse(report.findings.contains { $0.kind == .command && $0.value == "touch" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(try Data(contentsOf: script), Data("touch '\(marker.path)'\n".utf8))
    }

    func testSourceAndTraversalBudgetsRemainExplicitUnknown() async {
        let source = Data(String(repeating: "curl x\n", count: 100).utf8)
        let byteReport = await BashSkillSyntaxAnalyzer(budget: .init(maximumBytes: 8)).scan(file: "large.sh", utf8: source)
        XCTAssertEqual(byteReport.completion, .unknown)
        XCTAssertNil(byteReport.sourceSHA256)
        XCTAssertEqual(byteReport.findings.first?.reason, "sourceBudget")
        let nodeReport = await BashSkillSyntaxAnalyzer(budget: .init(maximumNodes: 5)).scan(file: "wide.sh", utf8: source)
        XCTAssertEqual(nodeReport.completion, .partial)
        XCTAssertLessThanOrEqual(nodeReport.visitedNodes, 5)
        XCTAssertTrue(nodeReport.findings.contains { $0.kind == .unknown })
        let findingReport = await BashSkillSyntaxAnalyzer(budget: .init(maximumFindings: 3)).scan(file: "facts.sh", utf8: source)
        XCTAssertEqual(findingReport.completion, .partial)
        XCTAssertLessThanOrEqual(findingReport.findings.count, 3)
        XCTAssertTrue(findingReport.findings.contains { $0.reason == "findingBudget" })
    }

    func testInvalidUTF8AndCancelledAnalysisAreNotEmptySuccess() async {
        let scanner = BashSkillSyntaxAnalyzer()
        let invalid = await scanner.scan(file: "invalid.sh", utf8: Data([0xff, 0xfe]))
        XCTAssertEqual(invalid.completion, .unknown)
        XCTAssertEqual(invalid.findings.first?.reason, "invalidUTF8")
        let task = Task { () -> SkillSyntaxReport in
            withUnsafeCurrentTask { $0?.cancel() }
            return await scanner.scan(file: "cancelled.sh", utf8: Data("curl x".utf8))
        }
        let cancelled = await task.value
        XCTAssertEqual(cancelled.completion, .unknown)
        XCTAssertEqual(cancelled.findings.first?.reason, "cancelled")
    }

    func testSHACacheIncludesSourceAndFileAndHasBoundedEviction() async {
        let scanner = BashSkillSyntaxAnalyzer()
        let first = await scanner.scan(file: "one.sh", utf8: Data("curl x".utf8))
        let hit = await scanner.scan(file: "one.sh", utf8: Data("curl x".utf8))
        XCTAssertEqual(first, hit)
        var count = await scanner.cachedReportCount
        XCTAssertEqual(count, 1)
        let changed = await scanner.scan(file: "one.sh", utf8: Data("jq x".utf8))
        XCTAssertNotEqual(first.sourceSHA256, changed.sourceSHA256)
        let renamed = await scanner.scan(file: "two.sh", utf8: Data("curl x".utf8))
        XCTAssertEqual(renamed.sourceSHA256, first.sourceSHA256)
        XCTAssertEqual(renamed.findings.first?.source.file, "two.sh")
        _ = await scanner.scan(file: "\u{e9}.sh", utf8: Data("curl x".utf8))
        let nfd = await scanner.scan(file: "e\u{301}.sh", utf8: Data("curl x".utf8))
        XCTAssertEqual(Array(nfd.file.utf8), Array("e\u{301}.sh".utf8))
        count = await scanner.cachedReportCount
        XCTAssertEqual(count, 5)
        for index in 0..<30 { _ = await scanner.scan(file: "\(index).sh", utf8: Data("printf ok".utf8)) }
        count = await scanner.cachedReportCount
        XCTAssertEqual(count, 16)
        await scanner.clearCache()
        count = await scanner.cachedReportCount
        XCTAssertEqual(count, 0)
    }

    func testActualPortableHelperJSONDecodesWithoutInventedBashProvenance() throws {
        for name in ["python-report-host", "typescript-report-host"] {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
            let report = try JSONDecoder().decode(SkillSyntaxReport.self, from: Data(contentsOf: url))
            XCTAssertEqual(report.completion, .complete)
            XCTAssertNotNil(report.sourceSHA256)
            XCTAssertFalse(report.provenance.engineVersion?.isEmpty ?? true)
            XCTAssertNil(report.provenance.wrapperRevision)
            XCTAssertNil(report.provenance.coreRevision)
            XCTAssertNil(report.provenance.grammarRevision)
            XCTAssertNil(report.provenance.languageABI)
            XCTAssertTrue(report.findings.contains { $0.kind == .moduleReference })
            XCTAssertEqual(try JSONDecoder().decode(SkillSyntaxReport.self,
                from: JSONEncoder().encode(report)), report)
        }
    }

    func testNonzeroDataSliceIsRebasedBeforeUTF8ParserAndSpanReads() async throws {
        let original = Data("prefixprintf 'שלום🙂'; curl x\n".utf8)
        let slice = original.dropFirst(6)
        XCTAssertEqual(slice.startIndex, 6)
        let scanner = BashSkillSyntaxAnalyzer()
        let report = await scanner.scan(file: "slice.sh", utf8: slice)
        let whole = await BashSkillSyntaxAnalyzer().scan(file: "slice.sh", utf8: Data(slice))
        XCTAssertEqual(report, whole)
        XCTAssertEqual(report.completion, .complete)
        XCTAssertEqual(report.inputBytes, slice.count)
        let curl = try XCTUnwrap(report.findings.first { $0.kind == .command && $0.value == "curl" })
        XCTAssertEqual(curl.source.byteOffset, Data("printf 'שלום🙂'; ".utf8).count)
        XCTAssertEqual(curl.source.byteLength, 4)
        let oversized = await BashSkillSyntaxAnalyzer(budget: .init(maximumBytes: 1)).scan(file: "slice.sh", utf8: slice)
        XCTAssertEqual(oversized.findings.first?.reason, "sourceBudget")
        XCTAssertNil(oversized.sourceSHA256)
    }
}
