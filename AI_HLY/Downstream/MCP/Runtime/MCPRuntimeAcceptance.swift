import Foundation

#if targetEnvironment(simulator)
private actor MCPAcceptanceProgressRecorder {
    private var terminalOperationIDs: Set<UUID> = []

    func record(_ progress: MCPInstallProgress) {
        if progress.terminalError != nil {
            terminalOperationIDs.insert(progress.operationID)
        }
    }

    func terminalErrorCount() -> Int { terminalOperationIDs.count }
}

struct MCPRuntimeAcceptanceResult: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let passed: Bool
    let nodeVersion: String?
    let modulePolicyHooksAvailable: Bool
    let packageName: String
    let resolvedVersion: String?
    let resolvedEntryPoint: String?
    let reachableModuleCount: Int?
    let resolvedModuleCount: Int?
    let clientStdioLoaded: Bool
    let crossSpawnLoaded: Bool
    let childProcessResolved: Bool
    let initializeSucceeded: Bool
    let toolsListSucceeded: Bool
    let toolCount: Int
    let harmlessToolSucceeded: Bool
    let workerStopped: Bool
    let terminalInstallErrorCount: Int
    let failureMessage: String?
}

@MainActor
enum MCPRuntimeAcceptance {
    static let resultFileName = "mcp-acceptance.json"
    private static let packageName = "@modelcontextprotocol/server-everything"
    private static let packageVersion = "2026.7.4"

    static func run(core: AppRuntimeCore = .shared, fileLayout: RuntimeFileLayout = .default) async {
        let service = MCPPackageInstallService(runtime: core.node)
        let registry = MCPServerRegistryStore()
        let controller = MCPRuntimeController(runtime: core.node, registry: registry)
        let progressRecorder = MCPAcceptanceProgressRecorder()
        var installation: MCPPackageInstallation?
        var descriptor: MCPServerDescriptor?
        var toolCount = 0
        var harmlessToolSucceeded = false
        var initializeSucceeded = false
        var toolsListSucceeded = false
        var workerStopped = false
        var failureMessage: String?

        do {
            try await core.prepareStorage()
            _ = try await core.node.ensureRunning()
            let spec = try MCPPackageSpec("\(packageName)@\(packageVersion)")
            let installed = try await service.install(
                spec,
                entryPointOverride: "dist/index.js",
                arguments: ["stdio"]
            ) { progress in
                await progressRecorder.record(progress)
            }
            installation = installed
            descriptor = installed.descriptor
            _ = try await registry.upsert(installed.descriptor)

            try await controller.start(installed.descriptor)
            initializeSucceeded = true
            let tools = try await controller.toolDescriptors(serverIDs: [installed.descriptor.id])
            toolsListSucceeded = true
            toolCount = tools.count
            guard !tools.isEmpty else {
                throw RuntimeCoreError.runtimeFailure("server-everything returned no tools during simulator acceptance.")
            }
            guard let echo = tools.first(where: { $0.originalName == "echo" }) else {
                throw RuntimeCoreError.runtimeFailure("server-everything did not expose its harmless echo tool.")
            }
            let output = try await controller.call(
                exposedName: echo.exposedName,
                argumentsJSON: #"{"message":"Hanlin RuntimeCore acceptance"}"#
            )
            guard !output.isError else {
                throw RuntimeCoreError.runtimeFailure("server-everything echo returned an MCP error.")
            }
            harmlessToolSucceeded = true
            await controller.stop(serverID: installed.descriptor.id)
            workerStopped = true
            try await service.commit(installed)
        } catch {
            failureMessage = error.localizedDescription
            if let installation {
                await controller.stop(serverID: installation.descriptor.id)
                do {
                    try await service.rollback(installation)
                } catch {
                    failureMessage = [failureMessage, error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
                }
            }
        }

        let snapshot = await core.node.snapshot()
        let report = descriptor?.compatibility
        let edges = report?.moduleEdges ?? []
        let terminalErrorCount = await progressRecorder.terminalErrorCount()
        let clientStdioLoaded = edges.contains { edge in
            edge.specifier == "@modelcontextprotocol/sdk/client/stdio.js"
                || edge.resolvedPath?.contains("/client/stdio.js") == true
        }
        let crossSpawnLoaded = edges.contains { edge in
            edge.specifier == "cross-spawn" || edge.resolvedPath?.contains("cross-spawn") == true
        }
        let childProcessResolved = edges.contains { edge in
            ["child_process", "node:child_process"].contains(edge.specifier)
                || edge.resolvedPath == "node:child_process"
        }
        let passed = failureMessage == nil
            && snapshot.version == NodeRuntimeService.expectedNodeVersion
            && report?.runtimeProbePassed == true
            && initializeSucceeded
            && toolsListSucceeded
            && toolCount > 0
            && harmlessToolSucceeded
            && workerStopped
            && !clientStdioLoaded
            && !crossSpawnLoaded
            && !childProcessResolved
            && terminalErrorCount == 0

        let result = MCPRuntimeAcceptanceResult(
            schemaVersion: 1,
            generatedAt: .now,
            passed: passed,
            nodeVersion: snapshot.version,
            modulePolicyHooksAvailable: snapshot.version == NodeRuntimeService.expectedNodeVersion,
            packageName: packageName,
            resolvedVersion: descriptor?.resolvedVersion,
            resolvedEntryPoint: report?.entryPoint,
            reachableModuleCount: report?.reachableModuleCount,
            resolvedModuleCount: report?.resolvedModuleCount,
            clientStdioLoaded: clientStdioLoaded,
            crossSpawnLoaded: crossSpawnLoaded,
            childProcessResolved: childProcessResolved,
            initializeSucceeded: initializeSucceeded,
            toolsListSucceeded: toolsListSucceeded,
            toolCount: toolCount,
            harmlessToolSucceeded: harmlessToolSucceeded,
            workerStopped: workerStopped,
            terminalInstallErrorCount: terminalErrorCount,
            failureMessage: failureMessage
        )

        do {
            try fileLayout.prepareIfNeeded()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(
                to: fileLayout.logs.appending(path: resultFileName),
                options: .atomic
            )
        } catch {
            preconditionFailure("Could not persist MCP acceptance result: \(error.localizedDescription)")
        }

        if !result.passed {
            try? await Task.sleep(for: .seconds(5))
            preconditionFailure(result.failureMessage ?? "MCP acceptance failed.")
        }
    }
}
#endif
