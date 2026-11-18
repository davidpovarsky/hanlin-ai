import Foundation
import HanlinPlatformContracts

/// Runtime05's application accessor. The original catalog/store/engines/job scheduler
/// remain authoritative. Rendering plans performs no engine start or script execution.
@MainActor
final class SkillRuntimeService {
    static let shared = SkillRuntimeService()
    typealias C = SkillRuntimeContract

    struct Receipt: Codable, Sendable {
        enum Status: String, Codable { case executionPass = "EXECUTION_PASS", failed = "FAILED", cancelled = "CANCELLED" }
        let status: Status
        let test: C.ExecutionTest?
        let result: RuntimeExecutionResult
        let recordedAt: Date
    }

    private let registry: SkillRuntimeRegistry
    private let bash = BashSkillSyntaxAnalyzer()
    private var analyses: [String: SkillSyntaxReport] = [:]
    private var eligibility: [String: (SkillRuntimeOpenClaw.Report, String, Date)] = [:]

    func policyEnvironmentSignature(store: SkillStore) async -> String {
        let values = await AppRuntimeCore.shared.snapshots().map {
            $0.kind.rawValue + ":" + ($0.version ?? "unknown") + ":" + String([.ready, .executing].contains($0.state))
        }
        var identity = Data((values.joined(separator: "\n") + "\nstore:" + String(store.revision) + "\n" + store.rootDirectoryURL.standardizedFileURL.path).utf8)
        let layout = RuntimeFileLayout.default
        for url in [layout.environmentRegistry, layout.nodeGlobalPackages.appending(path: "package-lock.json"),
                    layout.registry.appending(path: "PythonPackages.json")] {
            if let bytes = try? Data(contentsOf: url) {
                identity.append(0)
                identity.append(contentsOf: SkillRuntimeRequirements.digest(bytes).utf8)
            }
        }
        return SkillRuntimeRequirements.digest(identity)
    }

    init() {
        // Static, trusted original engine registrations, never supplied by imported metadata.
        do {
            registry = try SkillRuntimeRegistry(providers: RuntimeKind.allCases.map {
                SkillRuntimeFactsProvider(engineID: SkillRuntimeRequirements.engine($0))
            })
        } catch { preconditionFailure("Original engine identifiers must be unique") }
    }

    func sourceFingerprint(skillID: HanlinSkillID, catalog: HanlinSkillCatalog = .shared,
                           store: SkillStore = .shared) async throws -> String {
        guard let document = catalog.markdownDocument(for: skillID) else { throw RuntimeCoreError.invalidDependencyManifest }
        let urls = try catalog.sourceResourceURLs(for: skillID, store: store)
        let original = document.originalSource
        return try await Task.detached {
            var identity = original
            var total = original.count
            for (path, url) in urls {
                try Task.checkCancellation()
                let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                if path == "SKILL.md", bytes != original { throw RuntimeCoreError.invalidRequest("Skill metadata changed; reopen the current catalog entry") }
                total += bytes.count
                guard total <= 64 * 1_048_576 else { throw RuntimeCoreError.invalidRequest("Skill source byte budget exceeded") }
                identity.append(0); identity.append(contentsOf: path.utf8); identity.append(0)
                identity.append(contentsOf: SkillRuntimeRequirements.digest(bytes).utf8)
            }
            return SkillRuntimeRequirements.digest(identity)
        }.value
    }

    private func analysisKey(path: String, bytes: Data) -> String { path + ":" + SkillRuntimeRequirements.digest(bytes) }

    func plan(skillID: HanlinSkillID, path: String? = nil, engine: C.EngineID? = nil,
              arguments: [String] = [], catalog: HanlinSkillCatalog = .shared,
              store: SkillStore = .shared, forExecution: Bool = false) async throws -> C.ExecutionPlan {
        guard let document = catalog.markdownDocument(for: skillID) else { throw RuntimeCoreError.invalidDependencyManifest }
        let bytes: Data
        if let path {
            guard let url = catalog.resolveResourceURL(skillID: skillID, relativePath: path),
                  try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
                  try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RuntimeCoreError.invalidPath }
            bytes = try Data(contentsOf: url)
            guard bytes.count <= 1_048_576 else { throw RuntimeCoreError.invalidRequest("Skill analysis source exceeds 1 MiB.") }
        } else { bytes = document.originalSource }
        let syntax: SkillSyntaxReport?
        if let path, ["sh", "bash"].contains((path as NSString).pathExtension) {
            syntax = await bash.scan(file: path, utf8: bytes)
        } else { syntax = analyses[analysisKey(path: path ?? "SKILL.md", bytes: bytes)] }
        let sourceHash = SkillRuntimeRequirements.digest(document.originalSource)
        let signature = await policyEnvironmentSignature(store: store)
        let upstream = eligibility[sourceHash].flatMap { $0.1 == signature ? $0 : nil }
        let packageFingerprint = try await sourceFingerprint(skillID: skillID, catalog: catalog, store: store)
        var combined = syntax
        var manifestFindings: [SkillSyntaxFinding] = []
        var manifestsComplete = true
        if path != nil {
            for manifest in ["requirements.txt", "pyproject.toml", "package.json"] {
                guard let url = catalog.resolveResourceURL(skillID: skillID, relativePath: manifest) else { continue }
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= 1_048_576, let report = analyses[analysisKey(path: manifest, bytes: bytes)] else { manifestsComplete = false; continue }
                manifestsComplete = manifestsComplete && report.completion == .complete
                manifestFindings += report.findings
            }
            if let original = syntax {
                combined = .init(file: original.file, sourceSHA256: original.sourceSHA256,
                    completion: manifestsComplete ? original.completion : .partial, provenance: original.provenance,
                    findings: original.findings + manifestFindings, visitedNodes: original.visitedNodes,
                    inputBytes: original.inputBytes, limitations: original.limitations)
            }
        }
        let action = try SkillRuntimeRequirements.action(skillID: skillID.rawValue, document: document,
            path: path, bytes: bytes, engine: engine, arguments: arguments, environmentID: "skill/" + skillID.rawValue,
            syntax: combined, openClawReport: upstream?.0, packageFingerprint: packageFingerprint)
        let last = forExecution ? nil : try receipt(skillID: skillID, path: path, store: store)?.test
        return await registry.plan(action: action, lastTest: last,
            freshness: .init(notBefore: .now.addingTimeInterval(-86_400), now: .now),
            evaluationTime: { .now }, supplement: { facts in
                guard let upstream, upstream.0.known, let binding = facts.binding else { return [] }
                return [.init(requirement: .init(kind: .capability, name: "openclaw.policy", versionConstraint: nil),
                    binding: binding, status: upstream.0.rawUpstreamResult?.eligible == true ? .available : .unsupported,
                    resolvedVersion: "847611dc/policy", resolvedPath: nil,
                    evidence: .init(kind: .observed, producer: "OriginalOpenClawPolicy/NodeJob",
                        producerVersion: "847611dc", sourceID: binding.engineID.rawValue,
                        sourceVersion: binding.engineVersion, sourceFingerprint: binding.engineFingerprint,
                        observedAt: upstream.2, artifactReference: nil))]
            })
    }

    /// Explicit user action only. Starts the selected ORIGINAL engine, then reads facts.
    /// This does not execute imported code or turn a plan into execution evidence.
    func recheck(skillID: HanlinSkillID, path: String?, engine: C.EngineID?,
                 catalog: HanlinSkillCatalog = .shared, store: SkillStore = .shared) async throws -> C.ExecutionPlan {
        if let engine {
            guard let kind = SkillRuntimeRequirements.kind(engine) else { throw RuntimeCoreError.invalidRequest("Engine unavailable") }
            _ = try await AppRuntimeCore.shared.start(kind)
            if kind == .shell { _ = try await AppRuntimeCore.shared.ensureStarted(.node) }
        }
        try Task.checkCancellation()
        if let path { try await analyze(skillID: skillID, path: path, catalog: catalog, store: store) }
        else { try await inspectPolicy(skillID: skillID, catalog: catalog, store: store) }
        return try await plan(skillID: skillID, path: path, engine: engine, catalog: catalog, store: store)
    }

    func analyze(skillID: HanlinSkillID, path: String, catalog: HanlinSkillCatalog = .shared,
                 store: SkillStore = .shared) async throws {
        guard let url = catalog.resolveResourceURL(skillID: skillID, relativePath: path) else { throw RuntimeCoreError.invalidPath }
        let bytes = try Data(contentsOf: url)
        let report = try await SkillRuntimeAnalysis.scan(path: path, bytes: bytes)
        try Task.checkCancellation()
        guard catalog.resolveResourceURL(skillID: skillID, relativePath: path) == url,
              try Data(contentsOf: url) == bytes else { throw RuntimeCoreError.invalidRequest("Skill changed during analysis") }
        if analyses.count >= 64 { analyses.removeAll() }
        analyses[analysisKey(path: path, bytes: bytes)] = report
        for manifest in ["requirements.txt", "pyproject.toml", "package.json"] {
            guard let url = catalog.resolveResourceURL(skillID: skillID, relativePath: manifest) else { continue }
            let bytes = try Data(contentsOf: url)
            let facts = try await SkillRuntimeAnalysis.scan(path: manifest, bytes: bytes)
            try Task.checkCancellation()
            guard catalog.resolveResourceURL(skillID: skillID, relativePath: manifest) == url,
                  try Data(contentsOf: url) == bytes else { throw RuntimeCoreError.invalidRequest("Skill manifest changed during analysis") }
            analyses[analysisKey(path: manifest, bytes: bytes)] = facts
        }
        try await inspectPolicy(skillID: skillID, catalog: catalog, store: store)
    }

    private func inspectPolicy(skillID: HanlinSkillID, catalog: HanlinSkillCatalog, store: SkillStore) async throws {
        guard let document = catalog.markdownDocument(for: skillID),
              SkillRuntimeOpenClaw.requiresPolicy(document) || SkillRuntimeOpenClaw.hasInvocationMetadata(document) else { return }
        _ = try await AppRuntimeCore.shared.ensureStarted(.node)
        let signature = await policyEnvironmentSignature(store: store)
        if let inspected = try await SkillRuntimeOpenClaw.inspect(document, enabled: store.isSkillEnabled(id: skillID)) {
            try Task.checkCancellation()
            guard catalog.markdownDocument(for: skillID)?.originalSource == document.originalSource,
                  signature == (await policyEnvironmentSignature(store: store)) else {
                throw RuntimeCoreError.invalidRequest("Skill metadata or environment changed during policy inspection")
            }
            if eligibility.count >= 64 { eligibility.removeAll() }
            eligibility[SkillRuntimeRequirements.digest(document.originalSource)] = (inspected, signature, .now)
        }
    }

    func policyReport(skillID: HanlinSkillID, catalog: HanlinSkillCatalog = .shared,
                      store: SkillStore = .shared) async -> SkillRuntimeOpenClaw.Report? {
        guard let document = catalog.markdownDocument(for: skillID),
              let cached = eligibility[SkillRuntimeRequirements.digest(document.originalSource)],
              cached.1 == (await policyEnvironmentSignature(store: store)) else { return nil }
        return cached.0
    }

    func findings(skillID: HanlinSkillID, path: String?, catalog: HanlinSkillCatalog = .shared) -> [SkillSyntaxFinding] {
        ([path].compactMap { $0 } + ["requirements.txt", "pyproject.toml", "package.json"]).flatMap { file in
            guard let url = catalog.resolveResourceURL(skillID: skillID, relativePath: file),
                  let bytes = try? Data(contentsOf: url) else { return [] as [SkillSyntaxFinding] }
            return analyses[analysisKey(path: file, bytes: bytes)]?.findings ?? []
        }
    }

    func record(_ result: RuntimeExecutionResult, plan: C.ExecutionPlan,
                skillID: HanlinSkillID, path: String, store: SkillStore = .shared) throws {
        let passed = result.exitCode == 0 && !result.wasCancelled && !result.didTimeOut
        let status: Receipt.Status = result.wasCancelled ? .cancelled : passed ? .executionPass : .failed
        let test: C.ExecutionTest?
        if let binding = plan.binding, let invocation = plan.action.invocationFingerprint {
            test = .init(actionID: plan.action.id, sourceFingerprint: plan.action.sourceFingerprint,
                actionFingerprint: plan.action.actionFingerprint, invocationFingerprint: invocation,
                binding: binding, outcome: passed ? .passed : .failed,
                evidence: .init(kind: .tested, producer: "ExecuteSkillResourceTool/AppRuntimeCore/JobStore",
                    producerVersion: "1", sourceID: skillID.rawValue, sourceVersion: nil,
                    sourceFingerprint: plan.action.actionFingerprint, observedAt: .now,
                    artifactReference: result.executionID.uuidString))
        } else { test = nil }
        let receipt = Receipt(status: status, test: test, result: result, recordedAt: .now)
        let url = receiptURL(skillID: skillID, path: path, store: store)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func receipt(skillID: HanlinSkillID, path: String?, store: SkillStore = .shared) throws -> Receipt? {
        guard let path else { return nil }
        let url = receiptURL(skillID: skillID, path: path, store: store)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: url))
    }

    private func receiptURL(skillID: HanlinSkillID, path: String, store: SkillStore) -> URL {
        // Outside imported trees. Imported archives cannot supply a forged historical receipt.
        let key = SkillRuntimeRequirements.digest(Data((skillID.rawValue + "\0" + path).utf8))
        return store.rootDirectoryURL.appending(path: "execution-evidence", directoryHint: .isDirectory)
            .appending(path: key + ".json")
    }
}

/// Carried only by the authorized original Host invocation or the explicit Run button.
/// Imported metadata and historical transcripts cannot manufacture a live approval.
enum SkillRuntimeAuthorization {
    @TaskLocal static var approved = false
    @TaskLocal static var invocationSource: SkillInvocationSource = .model
}
