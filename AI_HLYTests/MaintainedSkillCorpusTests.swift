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
        try #require(plan.readiness == .likely && plan.isExecutable,
            "Original CPython resolution must establish the actual standard-library requirements before this failure test")
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


    @Test func originalPythonPackageFactsUseRealInstallAndInvalidateChangedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-module-facts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let distribution = "hanlin-module-fact-" + suffix
        let module = distribution.replacingOccurrences(of: "-", with: "_")
        let parentMarker = root.appending(path: "parent-imports.txt")
        let childMarker = root.appending(path: "child-imports.txt")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func literal(_ text: String) throws -> String { String(decoding: try encoder.encode(text), as: UTF8.self) }
        func archive(_ files: [String: Data], to url: URL) throws {
            let archive = try Archive(url: url, accessMode: .create)
            for name in files.keys.sorted() {
                let bytes = try #require(files[name])
                try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(bytes.count)) { offset, length in
                    bytes.subdata(in: Int(offset)..<(Int(offset) + length))
                }
            }
        }
        let parent = """
        from pathlib import Path
        marker = Path(\(try literal(parentMarker.path)))
        marker.write_text((marker.read_text() if marker.exists() else '') + 'parent\\n')
        __version__ = '1.0.0'
        """
        let child = """
        from pathlib import Path
        Path(\(try literal(childMarker.path))).write_text('actual-child-import')
        VALUE = 7
        """
        let metadata = module + "-1.0.0.dist-info/"
        var files: [String: Data] = [
            module + "/__init__.py": Data((parent + "\n").utf8),
            module + "/child.py": Data((child + "\n").utf8),
            metadata + "METADATA": Data("Metadata-Version: 2.3\nName: \(distribution)\nVersion: 1.0.0\n\n".utf8),
            metadata + "WHEEL": Data("Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n".utf8)
        ]
        let records = files.keys.sorted().map { name -> String in
            let bytes = files[name]!
            let digest = Data(SHA256.hash(data: bytes)).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return "\(name),sha256=\(digest),\(bytes.count)\n"
        }.joined() + metadata + "RECORD,,\n"
        files[metadata + "RECORD"] = Data(records.utf8)
        let wheel = root.appending(path: module + "-1.0.0-py3-none-any.whl")
        try archive(files, to: wheel)

        let manager = AppRuntimeCore.shared.pythonPackages
        var installed: PythonPackageRecord?
        func cleanOwnImportCache() async throws {
            let source = """
            import sys
            for name in tuple(sys.modules):
                if name == '\(module)' or name.startswith('\(module).'):
                    sys.modules.pop(name, None)
            """
            let result = try await AppRuntimeCore.shared.python.execute(.init(source: source, workspace: root))
            try #require(result.exitCode == 0 && !result.didTimeOut && !result.wasCancelled)
        }
        do {
            let package = try await manager.install(name: wheel.path, importName: module)
            installed = package
            try #require(package.normalizedName == distribution && package.version == "1.0.0")
            let importProbeMarker = try Data(contentsOf: parentMarker)
            #expect(String(decoding: importProbeMarker, as: UTF8.self) == "parent\n")
            #expect(!FileManager.default.fileExists(atPath: childMarker.path))

            let skillName = "python-facts-" + suffix
            let markdown = "---\nname: \(skillName)\ndescription: Actual local package fact inspection and cache invalidation\n---\nRun the owned local package check.\n"
            let script = "import \(module).child\nprint(\(module).child.VALUE)\n"
            let skillZip = root.appending(path: "skill.zip")
            try archive(["SKILL.md": Data(markdown.utf8), "scripts/check.py": Data(script.utf8)], to: skillZip)
            let staged = try SkillImporter().stageAndInspect(fileURL: skillZip)
            defer { staged.cleanup() }
            let store = SkillStore(rootDirectoryURL: root.appending(path: "store"), onCatalogChange: {})
            let record = try store.install(stagedPackage: staged)
            let catalog = catalogFor(record, store: store)
            let session = AssistantCapabilitySession(isTemporaryChat: true)
            let loaded = await LoadSkillTool.execute(argumentsJSON: try json(["skill_id": record.id.rawValue]),
                session: session, catalog: catalog, store: store)
            try #require(!loaded.hasPrefix("Error:") && session.isSkillLoaded(record.id))
            let service = SkillRuntimeService()
            try await service.analyze(skillID: record.id, path: "scripts/check.py", catalog: catalog, store: store)
            let initial = try await service.plan(skillID: record.id, path: "scripts/check.py",
                engine: .python, arguments: [], catalog: catalog, store: store)
            try #require(initial.isExecutable && initial.readiness == .likely && initial.lastTest == nil)
            #expect(try Data(contentsOf: parentMarker) == importProbeMarker,
                "Module inspection must not repeat the package manager's actual import side effect")
            #expect(!FileManager.default.fileExists(atPath: childMarker.path),
                "Dotted module resolution must not execute the child")

            let arguments = try json(["skill_id": record.id.rawValue, "relative_path": "scripts/check.py",
                "engine": RuntimeKind.localPython.rawValue, "arguments": [String]()])
            let result = await SkillRuntimeAuthorization.$approved.withValue(true) {
                await ExecuteSkillResourceTool(catalog: catalog, store: store).execute(argumentsJSON: arguments,
                    context: .init(localeIdentifier: "en", capabilitySession: session))
            }
            try #require(result.outcome.isSuccess, "\(result.modelText)")
            let receipt = try #require(try service.receipt(skillID: record.id, path: "scripts/check.py", store: store))
            try #require(receipt.status == .executionPass && receipt.result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "7")
            #expect(try String(contentsOf: childMarker, encoding: .utf8) == "actual-child-import")
            #expect(try String(contentsOf: parentMarker, encoding: .utf8) == "parent\nparent\n")

            // Establish a genuinely matching VERIFIED plan before mutation.
            // New argv, absent analysis, or simply deleting a receipt is not proof.
            try await service.analyze(skillID: record.id, path: "scripts/check.py", catalog: catalog, store: store)
            let unchanged = try await service.plan(skillID: record.id, path: "scripts/check.py",
                engine: .python, arguments: [], catalog: catalog, store: store)
            try #require(unchanged.readiness == .verified && unchanged.lastTest == receipt.test)
            let installedChild = RuntimeFileLayout.default.pythonPackages
                .appending(path: package.normalizedName + "-" + package.version)
                .appending(path: module + "/child.py")
            try Data((child.replacingOccurrences(of: "VALUE = 7", with: "VALUE = 8") + "\n").utf8)
                .write(to: installedChild, options: .atomic)
            let passiveWork = MaintainedSkillWorkWitness()
            let invalidated = try await RuntimeJobProgress.$reporter.withValue({ job in
                passiveWork.executionIDs.insert(job.executionID)
            }) {
                try await service.plan(skillID: record.id, path: "scripts/check.py",
                    engine: .python, arguments: [], catalog: catalog, store: store)
            }
            #expect(passiveWork.executionIDs.isEmpty)
            #expect(invalidated.readiness != .verified && invalidated.lastTest == nil)
            #expect(invalidated.binding?.environmentFingerprint != unchanged.binding?.environmentFingerprint)
            let historical = try service.receipt(skillID: record.id, path: "scripts/check.py", store: store)
            #expect(historical?.result.executionID == receipt.result.executionID && historical?.status == .executionPass)

            try await service.analyze(skillID: record.id, path: "scripts/check.py", catalog: catalog, store: store)
            let reanalyzed = try await service.plan(skillID: record.id, path: "scripts/check.py",
                engine: .python, arguments: [], catalog: catalog, store: store)
            #expect(reanalyzed.readiness == .likely && reanalyzed.lastTest == nil)
            #expect(reanalyzed.binding?.environmentFingerprint != unchanged.binding?.environmentFingerprint)
            #expect(try String(contentsOf: parentMarker, encoding: .utf8) == "parent\nparent\n",
                "Reanalysis must not replay successful package code")

            try await manager.uninstall(package)
            installed = nil
            try #require(try await manager.installed().allSatisfy { $0.normalizedName != distribution })
            try await cleanOwnImportCache()
            print("PYTHON_ORIGINAL_MODULE_FACTS " + (try json([
                "schema": 1, "fixture_kind": "generated local wheel; excluded from the maintained corpus count",
                "route": "PythonPackageManager local wheel / original CPython resolution / Skill ZIP / real execution / source mutation / uninstall",
                "wheel_sha256": package.sha256, "execution_id": receipt.result.executionID.uuidString,
                "unchanged_readiness": unchanged.readiness.rawValue,
                "changed_source_readiness": invalidated.readiness.rawValue,
                "reanalyzed_readiness": reanalyzed.readiness.rawValue,
                "passive_jobs": passiveWork.executionIDs.count, "historical_receipt_retained": historical?.result.executionID == receipt.result.executionID,
                "inspection_replayed_package": try String(contentsOf: parentMarker, encoding: .utf8) != "parent\nparent\n", "package_cleanup": "PASS", "external_requests": "NOT_RUN"
            ])))
        } catch {
            if let installed { try? await manager.uninstall(installed) }
            try? await cleanOwnImportCache()
            throw error
        }
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
