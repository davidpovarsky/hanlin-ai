import Foundation
import HanlinPlatformContracts
import HanlinSkillFormat
import Testing
import ZIPFoundation
@testable import AI_Hanlin

@Suite("Imported Skills through the original product execution path", .serialized)
@MainActor
struct SkillRuntimeProductTests {
    @Test func originalOpenClawSixCasesExecuteInTheActualEmbeddedAppEngine() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "openclaw-native-" + UUID().uuidString)
        let generated = root.appending(path: "generated")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (resource, ext, target) in [
            ("hanlin_openclaw_native_probe", "mjs", root.appending(path: "native-probe.mjs")),
            ("hanlin_openclaw_native_contract", "mjs", generated.appending(path: "native-contract.mjs")),
            ("hanlin_openclaw_requirements", "js", generated.appending(path: "requirements.js")),
            ("hanlin_openclaw_upstream_requirements_tests", "js", generated.appending(path: "upstream-requirements-tests.js")),
            ("hanlin_openclaw_provenance", "json", generated.appending(path: "provenance.json"))] {
            let source = try #require(Bundle.main.url(forResource: resource, withExtension: ext))
            try Data(contentsOf: source).write(to: target)
        }
        let challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let output = root.appending(path: "native-report.json")
        let result = try await AppRuntimeCore.shared.node.executeCLI(entryPoint: root.appending(path: "native-probe.mjs"),
            arguments: [challenge], workspace: root, environment: ["HANLIN_OPENCLAW_PROBE_RESULT": output.path])
        #expect(result.exitCode == 0, result.stderr)
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(report["challenge"] as? String == challenge)
        #expect(report["node"] as? String == "24.5.0")
        #expect(report["ok"] as? Bool == true)
        let cases = try #require(report["cases"] as? [[String: Any]])
        #expect(cases.count == 6 && cases.allSatisfy { $0["status"] as? String == "EXECUTED_PASS" })
        print("OPENCLAW_EMBEDDED_ORIGINAL_SIX " + String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
    }

    static let fixtures = ["instructions", "node", "python", "typescript", "jsc", "argv", "unicode",
        "missing-module", "unknown-engine", "disabled", "denied", "wrong-engine", "failure",
        "cancel", "restart", "reinstall", "openclaw"]

    @Test(arguments: fixtures)
    func importedSkillPlanExecuteAndReopen(_ fixture: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "skill-product-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillStore(rootDirectoryURL: root.appending(path: "store"), onCatalogChange: {})
        let name = "phase2-" + UUID().uuidString.lowercased()
        let nonce = UUID().uuidString.lowercased()
        let ext = fixture == "python" || fixture == "unicode" ? "py" : fixture == "typescript" ? "ts" : "js"
        let path = "scripts/run." + ext
        let source: String
        switch fixture {
        case "python", "unicode": source = "print('\(nonce) שלום مرحبا')\n"
        case "typescript": source = "const value: string = '\(nonce)'; console.log(value); export default value;"
        case "argv": source = "if(JSON.stringify(process.argv.slice(2))!==JSON.stringify(['\(nonce)','עברית']))throw Error('argv changed'); console.log('\(nonce)');"
        case "failure": source = "throw new Error('EXPECTED_FAILURE_\(nonce)');"
        case "cancel": source = "console.log('STARTED_\(nonce)'); await new Promise(resolve=>setTimeout(resolve,30000)); console.log('UNEXPECTED_LATE_\(nonce)');"
        default: source = "console.log('\(nonce)');"
        }
        var metadata = ""
        if fixture == "missing-module" { metadata = "requires:\n  modules: [hanlin_missing_package_\(nonce)]\n" }
        if fixture == "openclaw" { metadata = "metadata:\n  openclaw:\n    requires:\n      bins: [node]\n" }
        let markdown = "---\nname: \(name)\ndescription: Product acceptance \(fixture)\n\(metadata)---\n\nUse the imported resource.\n"
        let archiveURL = root.appending(path: "skill.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        var files = [("SKILL.md", Data(markdown.utf8))]
        if fixture != "instructions" { files.append((path, Data(source.utf8))) }
        for (file, bytes) in files {
            try archive.addEntry(with: file, type: .file, uncompressedSize: UInt32(bytes.count)) { position, size in
                bytes.subdata(in: position..<(position + size))
            }
        }
        let importer = SkillImporter()
        let staged = try importer.stageAndInspect(fileURL: archiveURL)
        defer { staged.cleanup() }
        let record = try store.install(stagedPackage: staged)
        let id = record.id
        let catalog = HanlinSkillCatalog()
        catalog.register(descriptor: record.descriptor, markdownDocument: record.markdownDocument,
            resourceResolver: { store.safeResourceURL(for: id, relativePath: $0) })
        let service = SkillRuntimeService()
        if fixture == "instructions" {
            let plan = try await service.plan(skillID: id, catalog: catalog, store: store)
            #expect(plan.action.kind == .instructions && !plan.isExecutable && plan.lastTest == nil)
            print("SKILL_PRODUCT PARSE_ONLY \(fixture) \(id.rawValue)")
            return
        }
        let engine: RuntimeKind = fixture == "python" || fixture == "unicode" ? .localPython
            : fixture == "typescript" ? .typeScript : fixture == "jsc" ? .javaScriptCore : .node
        let initial = try await service.plan(skillID: id, path: path,
            engine: SkillRuntimeRequirements.engine(engine), catalog: catalog, store: store)
        #expect(initial.lastTest == nil, "Import must not manufacture an execution test")
        if fixture == "disabled" { store.setSkillEnabled(id: id, enabled: false) }
        let session = AssistantCapabilitySession(chatID: "fixture-" + nonce, isTemporaryChat: true)
        session.recordSkillLoaded(id: id, instructionText: markdown)
        let selectedEngine = fixture == "wrong-engine" ? RuntimeKind.localPython.rawValue : fixture == "unknown-engine" ? "ish" : engine.rawValue
        let arguments = try JSONSerialization.data(withJSONObject: ["skill_id": id.rawValue,
            "relative_path": path, "engine": selectedEngine, "arguments": [nonce, "עברית"]])
        let tool = ExecuteSkillResourceTool(catalog: catalog, store: store)
        let (started, signal) = AsyncStream<UUID>.makeStream()
        let task = Task { @MainActor in
            defer { signal.finish() }
            return await RuntimeJobProgress.$reporter.withValue({ job in
                if fixture == "cancel", job.stdoutBytes > 0 {
                    let file = AppRuntimeCore.shared.jobs.directory(id: job.executionID, kind: .node).appending(path: "stdout.log")
                    if let text = try? String(contentsOf: file, encoding: .utf8), text.contains("STARTED_" + nonce) {
                        signal.yield(job.executionID)
                    }
                }
            }) {
                await SkillRuntimeAuthorization.$approved.withValue(fixture != "denied") {
                await tool.execute(argumentsJSON: String(decoding: arguments, as: UTF8.self),
                    context: .init(localeIdentifier: "he", capabilitySession: session))
                }
            }
        }
        if fixture == "cancel" {
            var runningJob: UUID?
            for await id in started { runningJob = id; break }
            #expect(runningJob != nil, "Cancellation must interrupt the actual script after its stdout witness")
            task.cancel()
        }
        let result = await task.value
        if ["missing-module", "unknown-engine", "disabled", "denied", "wrong-engine", "failure", "cancel"].contains(fixture) {
            #expect(!result.outcome.isSuccess, "\(fixture) incorrectly succeeded: \(result.modelText)")
            #expect(!result.modelText.contains("UNEXPECTED_LATE_" + nonce))
            if fixture == "cancel" {
                let receipt = try #require(service.receipt(skillID: id, path: path, store: store))
                #expect(receipt.status == .cancelled && receipt.result.wasCancelled)
                #expect(receipt.result.stdout.contains("STARTED_" + nonce))
            }
            print("SKILL_PRODUCT REJECTED_OR_FAILED \(fixture) \(result.outcome)")
            return
        }
        #expect(result.outcome.isSuccess, "\(fixture): \(result.modelText)")
        #expect(result.modelText.contains(nonce), "Original engine did not return the execution challenge")
        let reopened = SkillRuntimeService()
        let receipt = try #require(reopened.receipt(skillID: id, path: path, store: store))
        #expect(receipt.status == .executionPass && receipt.result.stdout.contains(nonce))
        #expect(receipt.test?.actionFingerprint == SkillRuntimeRequirements.digest(Data(source.utf8)))
        if fixture == "reinstall" {
            try store.addOrUpdateTextResource(for: id, relativePath: path, content: "console.log('changed-source');")
            let plan = try await reopened.plan(skillID: id, path: path,
                engine: SkillRuntimeRequirements.engine(engine), catalog: catalog, store: store)
            #expect(plan.lastTest == nil, "Old execution cannot verify changed source")
        }
        print("SKILL_PRODUCT EXECUTION_PASS \(fixture) job=\(receipt.result.executionID) source=\(receipt.test?.actionFingerprint ?? "missing")")
    }

    @Test(arguments: ["traversal", "malformed-yaml", "external-reference"])
    func hostileImportedArchivesAreRejectedBeforeInstallation(_ fixture: String) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "hostile.zip"), archive = try Archive(url: root.appending(path: "hostile.zip"), accessMode: .create)
        let markdown = fixture == "malformed-yaml" ? "---\nname: [invalid\n---\nbody"
            : "---\nname: hostile\ndescription: Hostile fixture\n---\nbody"
        let entries = fixture == "traversal" ? [("SKILL.md", markdown), ("../escape.txt", "must-not-write")]
            : fixture == "external-reference" ? [("SKILL.md", markdown), ("/absolute/escape.txt", "must-not-write")]
            : [("SKILL.md", markdown)]
        for (path, string) in entries {
            let bytes = Data(string.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: UInt32(bytes.count)) { position, size in
                bytes.subdata(in: position..<(position + size))
            }
        }
        do {
            let staged = try SkillImporter().stageAndInspect(fileURL: url)
            staged.cleanup(); Issue.record("Hostile fixture was admitted: \(fixture)")
        } catch { #expect(!FileManager.default.fileExists(atPath: root.appending(path: "escape.txt").path)) }
    }
}
