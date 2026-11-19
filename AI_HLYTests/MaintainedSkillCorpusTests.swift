import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinSkillFormat
import Testing
import ZIPFoundation
@testable import AI_Hanlin

/// Maintained, hash-pinned packages, not renamed synthetic execution fixtures.
/// A successful test proves the listed product routes. Remote business workflows
/// and physical-device execution remain separate acceptance requirements.
@Suite("Maintained Skills through the original product paths", .serialized)
@MainActor
struct MaintainedSkillCorpusTests {
    nonisolated static let names = [
        "apple-notes", "apple-reminders", "control-ui", "diagram-maker",
        "github", "gog", "healthcheck", "himalaya", "meme-maker", "model-usage",
        "node-connect", "node-inspect-debugger", "notion", "openai-whisper-api",
        "python-debugpy", "skill-creator", "tmux", "trello", "visualize", "weather",
        "yochai-study", "torah-photo-study", "cairo-genizah-research"
    ]
    nonisolated private static let manifestSHA256 = "d280d4c87a4068484ae5e046a667391d3c2b22026f630539efb81ff440995114"

    @Test(arguments: names)
    func maintainedPackagesFollowOriginalImportPolicyAndReadiness(_ name: String) async throws {
        let corpus = try loadCorpus()
        let entry = try #require(corpus.manifest.skills.first { $0.name == name })
        let root = FileManager.default.temporaryDirectory.appending(path: "maintained-skill-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let before = await AppRuntimeCore.shared.snapshots()
        let work = MaintainedSkillWorkWitness()
        let (store, record, catalog, instructionsPlan, passiveActions) = try await RuntimeJobProgress.$reporter.withValue({ job in
            work.executionIDs.insert(job.executionID)
        }) {
            let (store, record, catalog) = try install(entry, corpus: corpus.root, root: root)
            let service = SkillRuntimeService()
            let instructions = try await service.plan(skillID: record.id, catalog: catalog, store: store)
            #expect(instructions.action.kind == .instructions && !instructions.isExecutable)
            #expect(instructions.lastTest == nil, "Import cannot manufacture execution evidence")
            var actions: [[String: Any]] = []
            for action in entry.actions {
                let plan = try await service.plan(skillID: record.id, path: action.path,
                    engine: .init(rawValue: action.engine), catalog: catalog, store: store)
                #expect(plan.lastTest == nil && plan.readiness != .verified)
                #expect(plan.action.requirements.allSatisfy {
                    $0.evidence.sourceFingerprint == plan.action.sourceFingerprint
                })
                actions.append(actionWitness(action, plan: plan))
            }
            return (store, record, catalog, instructions, actions)
        }
        let after = await AppRuntimeCore.shared.snapshots()
        #expect(work.executionIDs.isEmpty, "ZIP import and passive compatibility must submit no runtime jobs")
        #expect(before.count == RuntimeKind.allCases.count && after.count == before.count)
        for current in after {
            let previous = try #require(before.first { $0.kind == current.kind })
            #expect(current.state == previous.state && current.activeExecutionCount == previous.activeExecutionCount,
                "Passive corpus import/readiness changed \(current.kind.rawValue)")
        }

        let document = try #require(record.markdownDocument)
        // This is an explicit preparation outside the passive-observation window,
        // so the real python3 requirement is supported by a real engine snapshot.
        if name == "python-debugpy" { _ = try await AppRuntimeCore.shared.ensureStarted(.localPython) }
        let visible = await catalog.modelVisibleSkills(store: store)
        let report = try await SkillRuntimeOpenClaw.inspect(document, enabled: true)
        if let report {
            #expect(report.factScope == "native" && !report.executionVerified)
            #expect(report.metadataStatus != "unsupported")
            if entry.invocationExpected {
                #expect(report.known && report.rawUpstreamResult?.eligible == true)
            } else {
                #expect(!report.known || report.rawUpstreamResult?.eligible == false)
            }
        } else {
            #expect(entry.invocationExpected, "A blocked package must have its actual declared policy")
        }
        #expect(visible.contains { $0.id == record.id } == entry.invocationExpected)
        #expect(try await catalog.permitsInvocation(record.id, source: .user, store: store) == entry.invocationExpected)
        #expect(try await catalog.permitsInvocation(record.id, source: .model, store: store) == entry.invocationExpected)

        let session = AssistantCapabilitySession(isTemporaryChat: true)
        let loadArguments = try json(["skill_id": record.id.rawValue])
        let loaded = await LoadSkillTool.execute(argumentsJSON: loadArguments, session: session, catalog: catalog, store: store)
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [])
        let executors = AssistantToolBridge.Executors(
            executeNative: { _, _, _, _ in
                Issue.record("Corpus instruction preparation unexpectedly invoked a native business tool")
                return NativeToolResult(modelText: "Unexpected corpus business execution", outcome: .failed)
            },
            executeScripting: { _, _ in
                Issue.record("Corpus instruction preparation unexpectedly invoked a script")
                return NativeToolResult(modelText: "Unexpected corpus script execution", outcome: .failed)
            })
        let adapter = HanlinAISDKToolAdapter(session: session,
            preparedTools: .init(authority: authority, executors: executors), catalog: catalog, skillStore: store)
        let prepared = await adapter.prepareStep(stepNumber: 0)
        if entry.invocationExpected {
            #expect(!loaded.hasPrefix("Error:") && session.isSkillLoaded(record.id))
            let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!body.isEmpty && loaded.contains(body))
            #expect(prepared.loadedSkillIDs == [record.id.rawValue])
            #expect(prepared.loadedSkillInstructions.contains { $0.contains(body) })
            for file in entry.files {
                let expected = try Data(contentsOf: corpus.root.appending(path: entry.directory).appending(path: file.path))
                let text = try #require(String(data: expected, encoding: .utf8))
                #expect(text.components(separatedBy: "\n").count <= 1000, "Extend pagination if the maintained source grows")
                let read = await ReadSkillResourceTool.execute(argumentsJSON: try json([
                    "skill_id": record.id.rawValue, "relative_path": file.path, "line_limit": 1000]),
                    session: session, catalog: catalog, store: store)
                #expect(!read.hasPrefix("Error:") && read.hasSuffix(text),
                    "The original resource must be readable without rewriting: \(name)/\(file.path)")
            }

            store.setSkillEnabled(id: record.id, enabled: false)
            let disabled = await adapter.prepareStep(stepNumber: 1)
            #expect(disabled.loadedSkillIDs.isEmpty && disabled.loadedSkillInstructions.isEmpty)
            let denied = await LoadSkillTool.execute(argumentsJSON: loadArguments, session: session, catalog: catalog, store: store)
            #expect(denied.hasPrefix("Error:"))
            let persistedDisabled = SkillStore(rootDirectoryURL: store.rootDirectoryURL, onCatalogChange: {})
            #expect(!persistedDisabled.isSkillEnabled(id: record.id))
            store.setSkillEnabled(id: record.id, enabled: true)
        } else {
            #expect(loaded.hasPrefix("Error:") && !session.isSkillLoaded(record.id))
            #expect(prepared.loadedSkillIDs.isEmpty && prepared.loadedSkillInstructions.isEmpty)
            let read = await ReadSkillResourceTool.execute(argumentsJSON: try json([
                "skill_id": record.id.rawValue, "relative_path": "SKILL.md"]),
                session: session, catalog: catalog, store: store)
            #expect(read.hasPrefix("Error:"))
        }

        // Explicit original-AST inspection is a separate operation from passive
        // compatibility. It analyzes source bytes and never executes that source.
        let service = SkillRuntimeService()
        var analyzedActions: [[String: Any]] = []
        for action in entry.actions {
            let engine = SkillRuntimeContract.EngineID(rawValue: action.engine)
            let kind = try #require(SkillRuntimeRequirements.kind(engine))
            _ = try await AppRuntimeCore.shared.ensureStarted(kind)
            try await service.analyze(skillID: record.id, path: action.path, catalog: catalog, store: store)
            let plan = try await service.plan(skillID: record.id, path: action.path, engine: engine, catalog: catalog, store: store)
            #expect(plan.lastTest == nil && plan.readiness != .verified,
                "Analysis/policy eligibility is not completed resource execution")
            #expect(try service.receipt(skillID: record.id, path: action.path, store: store) == nil)
            analyzedActions.append(actionWitness(action, plan: plan))
        }

        let reopened = SkillStore(rootDirectoryURL: store.rootDirectoryURL, onCatalogChange: {})
        let persisted = try #require(reopened.allStoredRecords().first { $0.id == record.id })
        #expect(persisted.markdownDocument?.originalSource == document.originalSource)
        try verifyInstalledBytes(entry, record: persisted, store: reopened, corpus: corpus.root)
        let reopenedCatalog = catalogFor(persisted, store: reopened)
        let reopenedSession = AssistantCapabilitySession(isTemporaryChat: true)
        let reopenedLoad = await LoadSkillTool.execute(argumentsJSON: loadArguments,
            session: reopenedSession, catalog: reopenedCatalog, store: reopened)
        #expect(reopenedLoad.hasPrefix("Error:") == !entry.invocationExpected)

        var witness: [String: Any] = [
            "schema": 1, "case": name, "manifest_sha256": Self.manifestSHA256,
            "source_repository": entry.repository, "source_commit": entry.revision,
            "original_file_count": entry.files.count, "original_sha256": Dictionary(uniqueKeysWithValues: entry.files.map { ($0.path, $0.sha256) }),
            "zip_import": "PASS", "installed_bytes": "PASS", "store_reopen_same_process": "PASS",
            "passive_runtime_jobs": work.executionIDs.count,
            "passive_before": states(before), "passive_after": states(after),
            "instruction_plan_readiness": instructionsPlan.readiness.rawValue,
            "instruction_plan_scope": "instruction availability only; not business execution",
            "invocation_expected": entry.invocationExpected,
            "catalog_load_read_sdk": entry.invocationExpected ? "PASS" : "POLICY_DENIED_AS_REQUIRED",
            "passive_actions": passiveActions, "analyzed_actions": analyzedActions,
            "external_business_workflow": "NOT_RUN", "physical_ipad": "NOT_RUN"
        ]
        if let report {
            witness["policy"] = [
                "scope": report.factScope, "metadata_status": report.metadataStatus,
                "known": report.known, "eligible": report.rawUpstreamResult?.eligible ?? false,
                "unobserved": report.unobserved, "execution_verified": report.executionVerified,
                "install_targets": report.installHints.map(\.target)
            ] as [String: Any]
        } else { witness["policy"] = ["declared_runtime_policy": "ABSENT"] }
        print("MAINTAINED_SKILL_CORPUS " + (try json(witness)))
    }

    @Test(arguments: ["scripts/browse.py", "scripts/search.py"])
    func cairoInvalidInputUsesTheCurrentRuntimePlan(_ path: String) async throws {
        let corpus = try loadCorpus()
        let entry = try #require(corpus.manifest.skills.first { $0.name == "cairo-genizah-research" })
        let root = FileManager.default.temporaryDirectory.appending(path: "maintained-cairo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, record, catalog) = try install(entry, corpus: corpus.root, root: root)
        let session = AssistantCapabilitySession(isTemporaryChat: true)
        let loaded = await LoadSkillTool.execute(argumentsJSON: try json(["skill_id": record.id.rawValue]),
            session: session, catalog: catalog, store: store)
        try #require(!loaded.hasPrefix("Error:") && session.isSkillLoaded(record.id))
        _ = try await AppRuntimeCore.shared.ensureStarted(.localPython)
        let service = SkillRuntimeService()
        try await service.analyze(skillID: record.id, path: path, catalog: catalog, store: store)
        let plan = try await service.plan(skillID: record.id, path: path, engine: .python,
            arguments: [], catalog: catalog, store: store)
        #expect(plan.lastTest == nil && plan.readiness != .verified)
        let arguments = try json(["skill_id": record.id.rawValue, "relative_path": path,
            "engine": RuntimeKind.localPython.rawValue, "arguments": [String]()])
        let result = await SkillRuntimeAuthorization.$approved.withValue(true) {
            await ExecuteSkillResourceTool(catalog: catalog, store: store).execute(
                argumentsJSON: arguments,
                context: .init(localeIdentifier: "he", capabilitySession: session))
        }
        #expect(!result.outcome.isSuccess, "Missing required argv must never yield a successful record")
        let receipt = try service.receipt(skillID: record.id, path: path, store: store)
        var status = "BLOCKED_BY_CURRENT_PLAN"
        if plan.isExecutable {
            let executed = try #require(receipt, "An executable invalid-input path must produce its real failure receipt")
            let usage = path.hasSuffix("browse.py") ? "Usage: browse.py <sys_id>" : "Usage: search.py <query> [limit]"
            #expect(executed.status == .failed && executed.result.exitCode == 1)
            #expect(executed.result.stdout.isEmpty && executed.result.stderr.contains(usage))
            #expect(executed.test?.binding.engineID == .python)
            let logs = AppRuntimeCore.shared.jobs.directory(id: executed.result.executionID, kind: .localPython)
            let durableError = try String(contentsOf: logs.appending(path: "stderr.log"), encoding: .utf8)
            #expect(durableError.contains(usage))
            let reopened = try SkillRuntimeService().receipt(skillID: record.id, path: path, store: store)
            #expect(reopened?.result.executionID == executed.result.executionID && reopened?.status == .failed)
            status = "EXPECTED_INVALID_INPUT_EXECUTED_WITH_DURABLE_FAILURE"
        } else {
            #expect(receipt == nil, "A planning rejection must not fabricate an executed failure")
            #expect(!plan.issues.isEmpty)
        }
        print("MAINTAINED_CAIRO_INVALID_INPUT " + (try json([
            "schema": 1, "path": path, "source_commit": entry.revision,
            "source_sha256": try #require(entry.files.first { $0.path == path }).sha256,
            "manifest_sha256": Self.manifestSHA256, "status": status,
            "plan_readiness": plan.readiness.rawValue, "plan_issues": plan.issues.map { $0.code.rawValue },
            "resource_execution_attempted": receipt != nil, "external_business_workflow": "NOT_RUN"
        ])))
    }

    private struct Manifest: Decodable { let schema: Int; let skills: [Entry]; let licenses: [File] }
    private struct Entry: Decodable {
        let name: String; let directory: String; let repository: String; let revision: String
        let invocationExpected: Bool; let files: [File]; let actions: [Action]
    }
    private struct File: Decodable { let path: String; let sha256: String; let gitBlob: String; let bytes: Int }
    private struct Action: Decodable { let path: String; let engine: String; let limitation: String }
    private struct Corpus { let root: URL; let manifest: Manifest }
    private final class ResourceMarker: NSObject {}

    private func loadCorpus() throws -> Corpus {
        let bundle = Bundle(for: ResourceMarker.self)
        let root = try #require(bundle.url(forResource: "MaintainedSkillCorpus", withExtension: "bundle", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "MaintainedSkillCorpus", withExtension: "bundle"))
        let bytes = try Data(contentsOf: root.appending(path: "corpus.json"))
        try #require(SkillRuntimeRequirements.digest(bytes) == Self.manifestSHA256, "The corpus lock changed")
        let manifest = try JSONDecoder().decode(Manifest.self, from: bytes)
        try #require(manifest.schema == 1 && manifest.skills.count == Self.names.count)
        try #require(Set(manifest.skills.map(\.name)) == Set(Self.names))
        for file in manifest.licenses { try verify(file, at: root.appending(path: file.path)) }
        return .init(root: root, manifest: manifest)
    }

    private func verify(_ file: File, at url: URL) throws {
        let bytes = try Data(contentsOf: url)
        try #require(bytes.count == file.bytes && SkillRuntimeRequirements.digest(bytes) == file.sha256,
            "Maintained source hash changed: \(file.path)")
        var object = Data("blob \(bytes.count)\0".utf8); object.append(bytes)
        let blob = Insecure.SHA1.hash(data: object).map { String(format: "%02x", $0) }.joined()
        try #require(blob == file.gitBlob, "Original Git blob changed: \(file.path)")
    }

    private func install(_ entry: Entry, corpus: URL, root: URL) throws -> (SkillStore, StoredSkillRecord, HanlinSkillCatalog) {
        let archive = try Archive(url: root.appending(path: "original-skill.zip"), accessMode: .create)
        for file in entry.files {
            try #require(!file.path.hasPrefix("/") && !file.path.split(separator: "/").contains(".."))
            let url = corpus.appending(path: entry.directory).appending(path: file.path)
            try verify(file, at: url)
            let bytes = try Data(contentsOf: url)
            try archive.addEntry(with: file.path, type: .file, uncompressedSize: Int64(bytes.count)) { position, size in
                let start = Int(position); return bytes.subdata(in: start..<(start + size))
            }
        }
        let staged = try SkillImporter().stageAndInspect(fileURL: root.appending(path: "original-skill.zip"),
            originURL: "https://github.com/" + entry.repository + "/tree/" + entry.revision)
        defer { staged.cleanup() }
        for resource in staged.resources where ["mjs", "cjs"].contains((resource.relativePath as NSString).pathExtension) {
            #expect(!resource.isBinary && resource.mimeType == "application/javascript")
        }
        let store = SkillStore(rootDirectoryURL: root.appending(path: "store"), onCatalogChange: {})
        let record = try store.install(stagedPackage: staged)
        try #require(record.id.rawValue == entry.name && record.sourceKind == .imported)
        try verifyInstalledBytes(entry, record: record, store: store, corpus: corpus)
        return (store, record, catalogFor(record, store: store))
    }

    private func verifyInstalledBytes(_ entry: Entry, record: StoredSkillRecord, store: SkillStore, corpus: URL) throws {
        let document = try #require(record.markdownDocument)
        let original = try Data(contentsOf: corpus.appending(path: entry.directory).appending(path: "SKILL.md"))
        #expect(document.originalSource == original && document.findings.isEmpty)
        for file in entry.files {
            let installed = try #require(store.safeResourceURL(for: record.id, relativePath: file.path))
            try verify(file, at: installed)
        }
        for resource in record.resources where ["mjs", "cjs"].contains((resource.relativePath as NSString).pathExtension) {
            #expect(!resource.isBinary && resource.mimeType == "application/javascript")
        }
    }

    private func catalogFor(_ record: StoredSkillRecord, store: SkillStore) -> HanlinSkillCatalog {
        let catalog = HanlinSkillCatalog()
        let id = record.id
        catalog.register(descriptor: record.descriptor, markdownDocument: record.markdownDocument,
            sourceDirectoryURL: record.directoryURL,
            resourceResolver: { store.safeResourceURL(for: id, relativePath: $0) })
        return catalog
    }

    private func actionWitness(_ action: Action, plan: SkillRuntimeContract.ExecutionPlan) -> [String: Any] {
        ["path": action.path, "selected_engine": action.engine,
         "source_sha256": plan.action.sourceFingerprint, "action_sha256": plan.action.actionFingerprint,
         "readiness": plan.readiness.rawValue, "is_executable": plan.isExecutable,
         "requirements": plan.action.requirements.map { $0.key.name },
         "issues": plan.issues.map { $0.code.rawValue },
         "execution_receipt": plan.lastTest == nil ? "ABSENT" : "PRESENT",
         "resource_execution": "NOT_RUN", "limitation": action.limitation]
    }

    private func states(_ snapshots: [RuntimeSnapshot]) -> [[String: Any]] {
        snapshots.map { ["kind": $0.kind.rawValue, "state": $0.state.rawValue, "active_executions": $0.activeExecutionCount] }
    }

    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
}

@MainActor
private final class MaintainedSkillWorkWitness {
    var executionIDs: Set<UUID> = []
}
