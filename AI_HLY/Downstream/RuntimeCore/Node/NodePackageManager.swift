import Foundation

struct NodePackageFinding: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(severity):\(message)" }
    let severity: String
    let message: String
}

struct LifecycleExecutionPlan: Codable, Hashable, Sendable {
    struct Action: Codable, Hashable, Sendable, Identifiable {
        var id: Self { self }
        let script: String
        let kind: String
        let command: String?
        let arguments: [String]
        let source: String?
        let workingDirectory: String?
        let packageName: String?
        let packageVersion: String?
        let packageIntegrity: String?
        let sourceOrigin: String?

        init(script: String, kind: String, command: String?, arguments: [String], source: String? = nil,
             workingDirectory: String? = nil, packageName: String? = nil, packageVersion: String? = nil,
             packageIntegrity: String? = nil, sourceOrigin: String? = nil) {
            self.script = script; self.kind = kind; self.command = command; self.arguments = arguments
            self.source = source; self.workingDirectory = workingDirectory; self.packageName = packageName
            self.packageVersion = packageVersion; self.packageIntegrity = packageIntegrity; self.sourceOrigin = sourceOrigin
        }
    }
    struct Rejection: Codable, Hashable, Sendable { let script: String; let reason: String }
    let packageName: String
    let packageVersion: String
    let integrity: String?
    let scriptHash: String
    let actions: [Action]
    let rejected: [Rejection]
    let requiresApproval: Bool
    let executable: Bool
    let schemaVersion: Int?
    let context: String?

    init(packageName: String, packageVersion: String, integrity: String?, scriptHash: String,
         actions: [Action], rejected: [Rejection], requiresApproval: Bool, executable: Bool,
         schemaVersion: Int? = nil, context: String? = nil) {
        self.packageName = packageName; self.packageVersion = packageVersion; self.integrity = integrity
        self.scriptHash = scriptHash; self.actions = actions; self.rejected = rejected
        self.requiresApproval = requiresApproval; self.executable = executable
        self.schemaVersion = schemaVersion; self.context = context
    }

}

struct NodePackageDetails: Codable, Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let version: String
    let requestedVersion: String?
    let summary: String?
    let nodeRequirement: String?
    let dependencies: [String]
    let integrity: String?
    let findings: [NodePackageFinding]?
    let lifecycle: LifecycleExecutionPlan?
    let packageRoot: String?
    let size: Int64?
    var validationStatus: String? = nil

    var entryPoint: String { packageRoot ?? "index.js" }
    var moduleKind: String { "commonjs" }
    var entryPoints: [String] { [entryPoint] }
    var dependencyCount: Int { dependencies.count }
    var compatibility: (verdict: String, isCompatible: Bool) {
        let hasUnsupported = findings?.contains(where: { $0.severity == "unsupported" }) ?? false
        return hasUnsupported ? ("unsupported", false) : ("compatible", true)
    }
}

private struct NodePackageInstallTransaction: Decodable, Sendable {
    let transactionID: String
    let packageRoot: String
    let package: NodePackageDetails
}

actor NodePackageManager {
    private struct PackageList: Decodable { let packages: [NodePackageDetails] }
    private let node: NodeRuntimeService
    private let lifecycle: LifecycleExecutionBroker
    private var operationTail: Task<Void, Never>?

    init(node: NodeRuntimeService, lifecycle: LifecycleExecutionBroker) {
        self.node = node
        self.lifecycle = lifecycle
    }

    func installed() async throws -> [NodePackageDetails] {
        let host = try await node.ensureRunning()
        return try await host.decode(PackageList.self, path: "/v1/packages/node").packages
    }

    func preview(name: String, version: String? = nil) async throws -> NodePackageDetails {
        let host = try await node.ensureRunning()
        var body: [String: Any] = ["name": name]
        if let version { body["version"] = version }
        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        return try await host.decode(NodePackageDetails.self, path: "/v1/packages/node/preview", method: "POST", body: encodedBody, timeout: 120)
    }

    // approveLifecycle is retained for source compatibility; execution is autonomous.
    func install(name: String, version: String? = nil, approveLifecycle: Bool = false) async throws -> NodePackageDetails {
        let previous = operationTail
        let task = Task {
            if let previous { await previous.value }
            try Task.checkCancellation()
            return try await performInstall(name: name, version: version)
        }
        operationTail = Task { _ = await task.result }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performInstall(name: String, version: String?) async throws -> NodePackageDetails {
        let host = try await node.ensureRunning()
        var body: [String: Any] = ["name": name]
        if let version { body["version"] = version }
        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        let transaction = try await node.stageNodePackage(
            NodePackageInstallTransaction.self,
            body: encodedBody
        )
        let transactionBody = try JSONSerialization.data(withJSONObject: ["transactionID": transaction.transactionID])
        do {
            if let plan = transaction.package.lifecycle {
                try await lifecycle.execute(plan, packageRoot: URL(fileURLWithPath: transaction.packageRoot, isDirectory: true))
            }
            let validation = try await probeStaged(transaction.package, workspace: URL(fileURLWithPath: transaction.package.packageRoot ?? transaction.packageRoot, isDirectory: true))
            try Task.checkCancellation()
            _ = try await host.data(path: "/v1/packages/node/commit", method: "POST", body: transactionBody, timeout: 60)
            let packages = try await installed()
            var installed = packages.first(where: { $0.name == transaction.package.name }) ?? transaction.package
            installed.validationStatus = Self.validationStatus(validation)
            return installed
        } catch {
            _ = try? await host.data(path: "/v1/packages/node/rollback", method: "POST", body: transactionBody, timeout: 30)
            throw error
        }
    }

    func uninstall(name: String) async throws {
        let previous = operationTail
        let task = Task {
            if let previous { await previous.value }
            try Task.checkCancellation()
            try await performUninstall(name: name)
        }
        operationTail = Task { _ = await task.result }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performUninstall(name: String) async throws {
        let host = try await node.ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        struct Removal: Decodable, Sendable {
            let transactionID: String
            let packageRoot: String
            let lifecycle: LifecycleExecutionPlan
        }
        let removal = try await node.stageNodePackage(Removal.self, removing: true, body: body)
        let transaction = try JSONSerialization.data(withJSONObject: ["transactionID": removal.transactionID])
        do {
            try await lifecycle.execute(removal.lifecycle, packageRoot: URL(fileURLWithPath: removal.packageRoot, isDirectory: true))
            try Task.checkCancellation()
            _ = try await host.data(path: "/v1/packages/node/commit", method: "POST", body: transaction)
        } catch {
            _ = try? await host.data(path: "/v1/packages/node/rollback", method: "POST", body: transaction)
            throw error
        }
    }

    func probe(_ package: NodePackageDetails) async throws -> RuntimeExecutionResult {
        guard let root = package.packageRoot else { throw RuntimeCoreError.invalidRequest("The installed package directory is unavailable.") }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
        return try await node.validatePackage(name: package.name, packageRoot: directory, workspace: directory)
    }

    static func validationStatus(_ result: RuntimeExecutionResult) -> String {
        guard result.exitCode == 0, !result.didTimeOut, !result.wasCancelled,
              case .object(let receipt) = result.value,
              case .string(let mode) = receipt["validationMode"] else { return "validationFailed" }
        switch mode {
        case "library-load":
            return receipt["executed"] == .boolean(true) ? "libraryLoadVerified" : "validationFailed"
        case "command-entry-files": return "commandFilesVerified"
        case "package-metadata": return "packageMetadataVerified"
        default: return "validationFailed"
        }
    }

    private func probeStaged(_ package: NodePackageDetails, workspace: URL) async throws -> RuntimeExecutionResult {
        guard let root = package.packageRoot else { throw RuntimeCoreError.invalidRequest("The staged package directory is unavailable.") }
        let result = try await node.validatePackage(name: package.name, packageRoot: URL(fileURLWithPath: root, isDirectory: true), workspace: workspace)
        guard result.exitCode == 0, !result.didTimeOut, !result.wasCancelled else {
            throw RuntimeCoreError.runtimeFailure(result.stderr)
        }
        return result
    }
}
