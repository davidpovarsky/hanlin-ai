import Foundation
import HanlinPlatformContracts
import HanlinSkillFormat
import Testing
import ZIPFoundation
@testable import AI_Hanlin

@Suite("Imported Skills through the original product execution path", .serialized)
@MainActor
struct SkillRuntimeProductTests {
    @Test(arguments: ["scalar", "array", "bins-scalar", "unknown-requirement", "always-string", "valid"])
    func openClawInputBoundaryRejectsUnsupportedShapes(_ fixture: String) async throws {
        let metadata: String
        switch fixture {
        case "scalar": metadata = "metadata: opaque-legacy-value\n"
        case "array": metadata = "metadata:\n  openclaw: []\n"
        case "bins-scalar": metadata = "metadata:\n  openclaw:\n    requires:\n      bins: node\n"
        case "unknown-requirement": metadata = "metadata:\n  openclaw:\n    requires:\n      unobservedGPU: []\n"
        case "always-string": metadata = "metadata:\n  openclaw:\n    always: 'yes'\n"
        default: metadata = "metadata:\n  openclaw:\n    requires:\n      bins: [node]\n"
        }
        let document = try SkillDocumentParser.parse(Data(("---\nname: boundary-test\ndescription: Typed input boundary\n" + metadata + "---\nInstructions\n").utf8))
        let bytes = Data("console.log('boundary')".utf8)
        let syntax = SkillSyntaxReport(file: "run.js", sourceSHA256: SkillRuntimeRequirements.digest(bytes),
            completion: .complete, provenance: .init(scanner: "synthetic-boundary-fixture"),
            findings: [], visitedNodes: 1, inputBytes: bytes.count, limitations: [])
        let action = try SkillRuntimeRequirements.action(skillID: "boundary-test", document: document,
            path: "run.js", bytes: bytes, engine: .node, arguments: [], environmentID: "boundary-test",
            syntax: syntax, openClawReport: try await SkillRuntimeOpenClaw.inspect(document))
        #expect(action.requirementsComplete == (fixture == "valid" || fixture == "bins-scalar"),
            "Only the actual original policy can accept normalized CSV/list metadata; opaque, unknown and malformed shapes remain incomplete")
    }

    @Test(arguments: ["requirements.txt", "pyproject.toml"])
    func nativeManifestAnalysisProducesTheExpectedPassiveFacts(_ file: String) async throws {
        let source = file == "requirements.txt" ? "hanlin-never-installed>=1\n"
            : "[project]\ndynamic = ['dependencies']\n"
        let bytes = Data(source.utf8)
        let report = try await SkillRuntimeAnalysis.scan(path: file, bytes: bytes)
        #expect(report.sourceSHA256 == SkillRuntimeRequirements.digest(bytes))
        #expect(report.provenance.scanner == "python.tomllib+packaging/26.3")
        #expect(report.visitedNodes > 0 && report.inputBytes == bytes.count)
        if file == "requirements.txt" {
            #expect(report.completion == .complete)
            #expect(report.findings.contains { $0.kind == .dependencyDeclaration
                && $0.value == "hanlin-never-installed>=1" && $0.reason == "declaredPEP508NotInstalled" })
        } else {
            #expect(report.completion == .partial)
            #expect(report.findings.contains { $0.kind == .unknown
                && $0.reason == "dynamicProjectMetadataNotExecuted" })
        }
        print("SKILL_NATIVE_PASSIVE_MANIFEST \(file) \(report.completion.rawValue) \(report.provenance.scanner)")
    }

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
        #expect(result.exitCode == 0, "\(result.stderr)")
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(report["challenge"] as? String == challenge)
        #expect(report["node"] as? String == "24.5.0")
        #expect(report["ok"] as? Bool == true)
        let cases = try #require(report["cases"] as? [[String: Any]])
        #expect(cases.count == 6 && cases.allSatisfy { $0["status"] as? String == "EXECUTED_PASS" })
        print("OPENCLAW_EMBEDDED_ORIGINAL_SIX " + String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
    }


    /// A selected fresh-process run additionally verifies the printed cold receipt.
    /// Exclude other engine-using suites; .serialized does not isolate peer suites.
    /// A warm full-suite invocation never claims to prove cold startup.
    @Test func ordinaryInstructionsLoadReadAndContinueWithoutRuntimeWork() async throws {
        let before = await AppRuntimeCore.shared.snapshots()
        let work = InstructionRuntimeWorkWitness()
        try await RuntimeJobProgress.$reporter.withValue({ job in
            work.executionIDs.insert(job.executionID)
        }) {
            try await importedSkillPlanExecuteAndReopen("instructions")
        }
        let after = await AppRuntimeCore.shared.snapshots()
        #expect(work.executionIDs.isEmpty, "Instruction loading must not submit runtime work")
        #expect(before.count == RuntimeKind.allCases.count && after.count == before.count)
        for snapshot in after {
            let original = try #require(before.first { $0.kind == snapshot.kind })
            #expect(snapshot.state == original.state,
                "Instruction loading changed \(snapshot.kind.rawValue) from \(original.state) to \(snapshot.state)")
            #expect(snapshot.activeExecutionCount == original.activeExecutionCount)
        }
        func states(_ snapshots: [RuntimeSnapshot]) -> [[String: Any]] {
            snapshots.map { ["kind": $0.kind.rawValue, "state": $0.state.rawValue,
                             "active_executions": $0.activeExecutionCount] }
        }
        let cold = before.allSatisfy { $0.state == .stopped && $0.activeExecutionCount == 0 }
            && after.allSatisfy { $0.state == .stopped && $0.activeExecutionCount == 0 }
            && work.executionIDs.isEmpty
        let receipt: [String: Any] = ["schema": 1, "cold_start_observed": cold,
            "before": states(before), "after": states(after), "observed_job_count": work.executionIDs.count,
            "route": "real ZIP import / model catalog / load / read / SDK / disable / re-enable"]
        print("SKILL_INSTRUCTIONS_RUNTIME_WITNESS " +
            String(decoding: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]), as: UTF8.self))
    }

    @Test func ordinaryInstructionsSurviveUnrelatedPolicyInspectionFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "instruction-policy-failure-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillStore(rootDirectoryURL: root.appending(path: "store"), onCatalogChange: {})
        let catalog = HanlinSkillCatalog()
        let id = try HanlinSkillID(validating: "ordinary-" + UUID().uuidString.lowercased())
        let instructions = "ORDINARY_INSTRUCTIONS_" + UUID().uuidString
        let resource = "ORDINARY_RESOURCE_" + UUID().uuidString
        let guide = root.appending(path: "guide.md")
        try Data(resource.utf8).write(to: guide)
        let ordinary = try SkillDocumentParser.parse(Data(
            "---\nname: \(id.rawValue)\ndescription: Ordinary instruction isolation\n---\n\(instructions)\n".utf8))
        #expect(ordinary.findings.isEmpty)
        let descriptor = try HanlinSkillDescriptor(id: id, title: "Ordinary instructions",
            summary: "Available independently of other policies", instructions: .inline(instructions))
        catalog.register(descriptor: descriptor, markdownDocument: ordinary,
            resourceResolver: { $0 == "guide.md" ? guide : nil })

        // Each valid Yams document fits its original 1 MiB limit; the genuine
        // combined policy DTO exceeds the existing 2 MiB execution boundary.
        var dependentIDs: Set<HanlinSkillID> = []
        for index in 0..<3 {
            let dependent = try HanlinSkillID(validating: "oversized-policy-\(index)")
            let markdown = "---\nname: \(dependent.rawValue)\ndescription: Bounded policy failure\nmetadata:\n  openclaw:\n    requires:\n      bins: [node]\n    padding: "
                + String(repeating: "x", count: 720 * 1024) + "\n---\nPolicy-dependent instructions\n"
            let document = try SkillDocumentParser.parse(Data(markdown.utf8))
            #expect(document.findings.isEmpty && SkillRuntimeOpenClaw.requiresPolicy(document))
            catalog.register(descriptor: try HanlinSkillDescriptor(id: dependent, title: "Dependent \(index)",
                summary: "Must stay unavailable after inspection fails",
                instructions: .inline("Policy-dependent instructions")), markdownDocument: document)
            dependentIDs.insert(dependent)
        }
        let visible = await catalog.modelVisibleSkills(store: store)
        #expect(visible.map(\.id) == [id])
        #expect(catalog.invocationPolicyError?.contains("byte budget") == true)
        #expect(Set(visible.map(\.id)).isDisjoint(with: dependentIDs))
        try await exerciseInstructionOnlySkill(id: id, catalog: catalog, store: store,
            instructions: instructions, relativePath: "guide.md", expectedResource: resource)
        print("SKILL_INSTRUCTIONS_POLICY_FAILURE_ISOLATED real_policy_byte_budget / load / read / SDK / enablement")
    }

    private func exerciseInstructionOnlySkill(id: HanlinSkillID, catalog: HanlinSkillCatalog,
        store: SkillStore, instructions: String, relativePath: String, expectedResource: String) async throws {
        let visible = await catalog.modelVisibleSkills(store: store)
        #expect(visible.contains { $0.id == id })
        #expect(try await catalog.permitsInvocation(id, source: .user, store: store))
        let session = AssistantCapabilitySession(isTemporaryChat: true)
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["skill_id": id.rawValue]), as: UTF8.self)
        let loaded = await LoadSkillTool.execute(argumentsJSON: args, session: session, catalog: catalog, store: store)
        #expect(!loaded.hasPrefix("Error:") && loaded.contains(instructions) && session.isSkillLoaded(id))
        let readArgs = String(decoding: try JSONSerialization.data(withJSONObject:
            ["skill_id": id.rawValue, "relative_path": relativePath]), as: UTF8.self)
        let read = await ReadSkillResourceTool.execute(argumentsJSON: readArgs, session: session, catalog: catalog, store: store)
        #expect(!read.hasPrefix("Error:") && read.contains(expectedResource))
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [])
        let executors = AssistantToolBridge.Executors(
            executeNative: { _, _, _, _ in NativeToolResult(modelText: "No execution in an instruction-only Skill", outcome: .failed) },
            executeScripting: { _, _ in NativeToolResult(modelText: "No execution in an instruction-only Skill", outcome: .failed) })
        let adapter = HanlinAISDKToolAdapter(session: session,
            preparedTools: .init(authority: authority, executors: executors), catalog: catalog, skillStore: store)
        let prepared = await adapter.prepareStep(stepNumber: 0)
        #expect(prepared.loadedSkillIDs == [id.rawValue])
        #expect(prepared.loadedSkillInstructions.contains { $0.contains(instructions) })

        store.setSkillEnabled(id: id, enabled: false)
        #expect(try await !catalog.permitsInvocation(id, source: .user, store: store))
        #expect(try await !catalog.permitsInvocation(id, source: .model, store: store))
        let deniedRead = await ReadSkillResourceTool.execute(argumentsJSON: readArgs, session: session, catalog: catalog, store: store)
        #expect(deniedRead.hasPrefix("Error:") && !deniedRead.contains(expectedResource))
        let deniedLoad = await LoadSkillTool.execute(argumentsJSON: args, session: session, catalog: catalog, store: store)
        #expect(deniedLoad.hasPrefix("Error:"))
        let disabled = await adapter.prepareStep(stepNumber: 1)
        #expect(disabled.loadedSkillIDs.isEmpty && disabled.loadedSkillInstructions.isEmpty)
        store.setSkillEnabled(id: id, enabled: true)
        #expect(try await catalog.permitsInvocation(id, source: .model, store: store))
        #expect(!session.isSkillLoaded(id), "Re-enabling must require a new explicit load")
    }

    nonisolated static let fixtures = ["instructions", "node", "python", "typescript", "jsc", "argv", "unicode",
        "missing-module", "unknown-engine", "disabled", "denied", "wrong-engine", "failure",
        "cancel", "restart", "reinstall", "openclaw", "shell", "requirements", "toml", "package-manifest", "hidden-resource"]

    @Test(arguments: fixtures)
    func importedSkillPlanExecuteAndReopen(_ fixture: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "skill-product-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillStore(rootDirectoryURL: root.appending(path: "store"), onCatalogChange: {})
        let name = "phase2-" + UUID().uuidString.lowercased()
        let nonce = UUID().uuidString.lowercased()
        let ext = ["python", "unicode", "requirements", "toml"].contains(fixture) ? "py" : fixture == "typescript" ? "ts" : fixture == "shell" ? "sh" : "js"
        let path = "scripts/run." + ext
        let source: String
        switch fixture {
        case "python", "unicode", "requirements", "toml": source = "print('\(nonce) שלום مرحبا')\n"
        // Use the original linked native command catalog, which does not claim
        // Yarn/Bash builtins such as echo as native command capabilities.
        // Positional expansions intentionally remain UNKNOWN in passive Bash
        // analysis. This case proves the real native command/quoting route;
        // the separate argv case verifies argument preservation through Node.
        case "shell": source = "awk 'BEGIN { print \"\(nonce)\"; exit }'\n"
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
        if fixture == "requirements" { files.append(("requirements.txt", Data("hanlin-never-installed>=1\n".utf8))) }
        if fixture == "toml" { files.append(("pyproject.toml", Data("[project]\ndynamic = ['dependencies']\n".utf8))) }
        if fixture == "package-manifest" { files.append(("package.json", Data(#"{"dependencies":{"hanlin-never-installed":"^1"}}"#.utf8))) }
        if fixture == "hidden-resource" { files.append((".helper.txt", Data("first source".utf8))) }
        for (file, bytes) in files {
            try archive.addEntry(with: file, type: .file, uncompressedSize: Int64(bytes.count)) { position, size in
                let offset = Int(position)
                return bytes.subdata(in: offset..<(offset + size))
            }
        }
        let importer = SkillImporter()
        let staged = try importer.stageAndInspect(fileURL: archiveURL)
        defer { staged.cleanup() }
        let record = try store.install(stagedPackage: staged)
        let id = record.id
        let catalog = HanlinSkillCatalog()
        catalog.register(descriptor: record.descriptor, markdownDocument: record.markdownDocument,
            sourceDirectoryURL: record.directoryURL,
            resourceResolver: { store.safeResourceURL(for: id, relativePath: $0) })
        let service = SkillRuntimeService()
        if fixture == "instructions" {
            let plan = try await service.plan(skillID: id, catalog: catalog, store: store)
            #expect(plan.action.kind == .instructions && !plan.isExecutable && plan.lastTest == nil)
            try await exerciseInstructionOnlySkill(id: id, catalog: catalog, store: store,
                instructions: "Use the imported resource.", relativePath: "SKILL.md", expectedResource: name)
            print("SKILL_PRODUCT INSTRUCTIONS_LOADED \(fixture) \(id.rawValue)")
            return
        }
        let engine: RuntimeKind = ["python", "unicode", "requirements", "toml"].contains(fixture) ? .localPython
            : fixture == "typescript" ? .typeScript : fixture == "jsc" ? .javaScriptCore : fixture == "shell" ? .shell : .node
        let initial = try await service.plan(skillID: id, path: path,
            engine: SkillRuntimeRequirements.engine(engine), catalog: catalog, store: store)
        #expect(initial.lastTest == nil, "Import must not manufacture an execution test")
        #expect(initial.action.requirements.allSatisfy { $0.evidence.sourceFingerprint == initial.action.sourceFingerprint },
            "Declared requirements must bind to the selected complete source generation")
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
        if ["missing-module", "unknown-engine", "disabled", "denied", "wrong-engine", "failure", "cancel", "requirements", "toml", "package-manifest"].contains(fixture) {
            #expect(!result.outcome.isSuccess, "\(fixture) incorrectly succeeded: \(result.modelText)")
            #expect(!result.modelText.contains("UNEXPECTED_LATE_" + nonce))
            if fixture == "cancel" {
                let recorded = try service.receipt(skillID: id, path: path, store: store)
                let receipt = try #require(recorded)
                #expect(receipt.status == .cancelled && receipt.result.wasCancelled)
                #expect(receipt.result.stdout.contains("STARTED_" + nonce))
            }
            if fixture == "failure" {
                let recorded = try service.receipt(skillID: id, path: path, store: store)
                let receipt = try #require(recorded)
                #expect(receipt.status == .failed && receipt.result.stderr.contains("EXPECTED_FAILURE_" + nonce),
                    "The intentionally throwing resource must actually execute; a planning rejection is not this test")
            }
            print("SKILL_PRODUCT REJECTED_OR_FAILED \(fixture) \(result.outcome)")
            return
        }
        try #require(result.outcome.isSuccess, "\(fixture): \(result.modelText)")
        try #require(result.modelText.contains(nonce), "Original engine did not return the execution challenge")
        let reopened = SkillRuntimeService()
        let recorded = try reopened.receipt(skillID: id, path: path, store: store)
        let receipt = try #require(recorded)
        try #require(receipt.status == .executionPass && receipt.result.stdout.contains(nonce))
        #expect(receipt.test?.actionFingerprint == SkillRuntimeRequirements.digest(Data(source.utf8)))
        if fixture == "hidden-resource" || fixture == "reinstall" {
            // Reopen with the same actual invocation and completed analysis first:
            // an empty analysis cache or different argv is not source invalidation.
            try await reopened.analyze(skillID: id, path: path, catalog: catalog, store: store)
            let originalTest = try #require(receipt.test)
            let unchanged = try await reopened.plan(skillID: id, path: path,
                engine: SkillRuntimeRequirements.engine(engine), arguments: [nonce, "עברית"],
                catalog: catalog, store: store)
            try #require(unchanged.readiness == .verified && unchanged.lastTest == originalTest,
                "The unchanged invocation must reuse its genuine successful execution before mutation")
            if fixture == "hidden-resource" {
                try store.addOrUpdateTextResource(for: id, relativePath: ".helper.txt", content: "changed helper")
            } else {
                try store.addOrUpdateTextResource(for: id, relativePath: path, content: "console.log('changed-source');")
            }
            try await reopened.analyze(skillID: id, path: path, catalog: catalog, store: store)
            let changed = try await reopened.plan(skillID: id, path: path,
                engine: SkillRuntimeRequirements.engine(engine), arguments: [nonce, "עברית"],
                catalog: catalog, store: store)
            #expect(changed.action.requirementsComplete && changed.readiness == .likely)
            #expect(changed.lastTest == nil, "Changed source cannot retain an old execution pass")
            #expect(changed.binding == unchanged.binding)
            #expect(changed.action.invocationFingerprint == unchanged.action.invocationFingerprint)
            #expect(changed.action.sourceFingerprint != unchanged.action.sourceFingerprint)
            if fixture == "hidden-resource" {
                #expect(changed.action.actionFingerprint == unchanged.action.actionFingerprint,
                    "The executable is unchanged; the hidden helper invalidates the complete source identity")
            } else {
                #expect(changed.action.actionFingerprint != unchanged.action.actionFingerprint)
            }
            #expect(try reopened.receipt(skillID: id, path: path, store: store)?.test == originalTest,
                "Invalidation must reject the old receipt without deleting or rewriting its evidence")
            print("SKILL_PRODUCT CACHE_INVALIDATION \(fixture) verified_before=true same_argv=true receipt_preserved=true")
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
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { position, size in
                let offset = Int(position)
                return bytes.subdata(in: offset..<(offset + size))
            }
        }
        do {
            let staged = try SkillImporter().stageAndInspect(fileURL: url)
            staged.cleanup(); Issue.record("Hostile fixture was admitted: \(fixture)")
        } catch { #expect(!FileManager.default.fileExists(atPath: root.appending(path: "escape.txt").path)) }
    }
}

@MainActor
private final class InstructionRuntimeWorkWitness {
    var executionIDs: Set<UUID> = []
}
