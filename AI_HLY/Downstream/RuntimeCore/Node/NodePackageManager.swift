import Foundation

struct NodePackageFinding: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(severity):\(message)" }
    let severity: String
    let message: String
}

struct LifecycleExecutionPlan: Codable, Hashable, Sendable {
    struct Action: Codable, Hashable, Sendable, Identifiable {
        var id: String { "\(script):\(kind):\(command ?? ""):\(arguments.joined(separator: ":"))" }
        let script: String
        let kind: String
        let command: String?
        let arguments: [String]
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
}

actor NodePackageManager {
    private struct PackageList: Decodable { let packages: [NodePackageDetails] }
    private let node: NodeRuntimeService

    init(node: NodeRuntimeService) { self.node = node }

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

    func install(name: String, version: String? = nil) async throws -> NodePackageDetails {
        let host = try await node.ensureRunning()
        var body: [String: Any] = ["name": name]
        if let version { body["version"] = version }
        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        return try await host.decode(NodePackageDetails.self, path: "/v1/packages/node/install", method: "POST", body: encodedBody, timeout: 600)
    }

    func uninstall(name: String) async throws {
        let host = try await node.ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        _ = try await host.data(path: "/v1/packages/node/uninstall", method: "POST", body: body, timeout: 600)
    }

    func probe(_ package: NodePackageDetails) async throws -> RuntimeExecutionResult {
        let encodedName = try JSONEncoder().encode(package.name)
        let literal = String(decoding: encodedName, as: UTF8.self)
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "node-package-probe")
        return try await node.executeJavaScript(RuntimeExecutionRequest(
            source: "const imported = await import(\(literal)); console.log(imported.default?.version ?? imported.version ?? 'import-ok'); export default { imported: true };",
            workspace: workspace
        ))
    }
}
