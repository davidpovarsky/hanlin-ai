import CryptoKit
import Foundation

struct LifecycleApprovalRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String { approvalKey }
    let packageName: String
    let packageVersion: String
    let packageIntegrity: String
    let scriptHash: String
    let approvedAt: Date

    var approvalKey: String {
        Self.key(packageName: packageName, version: packageVersion, integrity: packageIntegrity, scriptHash: scriptHash)
    }

    static func key(packageName: String, version: String, integrity: String, scriptHash: String) -> String {
        let value = [packageName, version, integrity, scriptHash].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

actor LifecycleExecutionBroker {
    private let node: NodeRuntimeService
    private let typeScript: TypeScriptRuntimeService
    private let python: PythonRuntimeService
    private let shell: ShellRuntimeService
    private let fileLayout: RuntimeFileLayout
    private var cachedApprovals: [LifecycleApprovalRecord]?

    init(
        node: NodeRuntimeService,
        typeScript: TypeScriptRuntimeService,
        python: PythonRuntimeService,
        shell: ShellRuntimeService,
        fileLayout: RuntimeFileLayout = .default
    ) {
        self.node = node
        self.typeScript = typeScript
        self.python = python
        self.shell = shell
        self.fileLayout = fileLayout
    }

    func isApproved(_ plan: LifecycleExecutionPlan) throws -> Bool {
        guard let integrity = plan.integrity else { return false }
        let key = LifecycleApprovalRecord.key(
            packageName: plan.packageName,
            version: plan.packageVersion,
            integrity: integrity,
            scriptHash: plan.scriptHash
        )
        return try approvals().contains { $0.approvalKey == key }
    }

    func approve(_ plan: LifecycleExecutionPlan) throws {
        guard plan.executable, plan.rejected.isEmpty else {
            throw RuntimeCoreError.invalidRequest("Rejected lifecycle commands cannot be approved.")
        }
        guard let integrity = plan.integrity, !integrity.isEmpty,
              plan.scriptHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw RuntimeCoreError.invalidRequest("Lifecycle approval requires verified package integrity and a script hash.")
        }
        var values = try approvals().filter {
            !($0.packageName == plan.packageName && $0.packageVersion == plan.packageVersion)
        }
        values.append(LifecycleApprovalRecord(
            packageName: plan.packageName,
            packageVersion: plan.packageVersion,
            packageIntegrity: integrity,
            scriptHash: plan.scriptHash,
            approvedAt: .now
        ))
        try persist(values)
    }

    func executeApproved(_ plan: LifecycleExecutionPlan, packageRoot: URL) async throws {
        guard plan.executable, plan.rejected.isEmpty else {
            throw RuntimeCoreError.invalidRequest("The lifecycle plan contains rejected commands.")
        }
        guard !plan.requiresApproval || (try isApproved(plan)) else {
            throw RuntimeCoreError.invalidRequest("Lifecycle execution requires explicit approval for this exact package version, integrity, and script hash.")
        }
        let workspace = try fileLayout.validatedDescendant(packageRoot, of: fileLayout.clients, allowRoot: false)
        for action in plan.actions {
            try Task.checkCancellation()
            switch action.kind {
            case "node":
                try await executeNode(action, workspace: workspace)
            case "typescript":
                let result = try await typeScript.compileProject(workspace: workspace, arguments: action.arguments)
                guard result.succeeded else {
                    throw RuntimeCoreError.runtimeFailure(result.diagnostics.map(\.message).joined(separator: "\n"))
                }
            case "python":
                try await executePython(action, workspace: workspace)
            case "fileUtility":
                guard let command = action.command else { throw RuntimeCoreError.invalidRequest("Lifecycle file utility is missing its command.") }
                let result = try await shell.execute(tokens: [command] + action.arguments, workspace: workspace, environment: [:], allowNetwork: false)
                guard result.exitCode == 0 else { throw RuntimeCoreError.runtimeFailure(result.stderr) }
            default:
                throw RuntimeCoreError.invalidRequest("Unsupported lifecycle action kind: \(action.kind)")
            }
        }
    }

    private func executeNode(_ action: LifecycleExecutionPlan.Action, workspace: URL) async throws {
        guard let script = action.arguments.first else { throw RuntimeCoreError.invalidRequest("Node lifecycle action is missing a script.") }
        let scriptURL = try containedFile(script, workspace: workspace)
        let pathLiteral = String(decoding: try JSONEncoder().encode(scriptURL.path), as: UTF8.self)
        let argumentsLiteral = String(decoding: try JSONEncoder().encode(Array(action.arguments.dropFirst())), as: UTF8.self)
        let source = """
        import { pathToFileURL } from 'node:url';
        process.argv = ['node', \(pathLiteral), ...\(argumentsLiteral)];
        await import(pathToFileURL(\(pathLiteral)).href);
        """
        let result = try await node.executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace))
        guard result.exitCode == 0, !result.didTimeOut, !result.wasCancelled else {
            throw RuntimeCoreError.runtimeFailure(result.stderr)
        }
    }

    private func executePython(_ action: LifecycleExecutionPlan.Action, workspace: URL) async throws {
        guard let script = action.arguments.first else { throw RuntimeCoreError.invalidRequest("Python lifecycle action is missing a script.") }
        let scriptURL = try containedFile(script, workspace: workspace)
        let source = try String(contentsOf: scriptURL, encoding: .utf8)
        let result = try await python.execute(RuntimeExecutionRequest(
            source: source,
            arguments: Array(action.arguments.dropFirst()),
            workspace: workspace
        ))
        guard result.exitCode == 0, !result.didTimeOut, !result.wasCancelled else {
            throw RuntimeCoreError.runtimeFailure(result.stderr)
        }
    }

    private func containedFile(_ relativePath: String, workspace: URL) throws -> URL {
        guard !relativePath.hasPrefix("/") else { throw RuntimeCoreError.pathEscapesRoot }
        let file = try fileLayout.validatedDescendant(workspace.appending(path: relativePath), of: workspace, allowRoot: false)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw RuntimeCoreError.invalidPath }
        return file
    }

    private func approvals() throws -> [LifecycleApprovalRecord] {
        if let cachedApprovals { return cachedApprovals }
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: fileLayout.lifecycleApprovalRegistry.path) else {
            cachedApprovals = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let values = try decoder.decode([LifecycleApprovalRecord].self, from: Data(contentsOf: fileLayout.lifecycleApprovalRegistry))
        cachedApprovals = values
        return values
    }

    private func persist(_ values: [LifecycleApprovalRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(values).write(to: fileLayout.lifecycleApprovalRegistry, options: [.atomic, .completeFileProtection])
        cachedApprovals = values
    }
}
