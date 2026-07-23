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

private struct MCPHostDiagnostics: Decodable {
    struct ServerLifecycle: Decodable {
        let maximumSimultaneousWorkers: Int
        let forcedTerminationCount: Int
    }

    struct Lifecycle: Decodable {
        let byServer: [String: ServerLifecycle]
    }

    let lifecycle: Lifecycle
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
    let lazyStartSucceeded: Bool
    let duplicateStartWasIdempotent: Bool
    let duplicateStopWasIdempotent: Bool
    let restartStressPassed: Bool
    let backgroundStopPassed: Bool
    let foregroundLazyRestartPassed: Bool
    let registryPreserved: Bool
    let maximumConcurrentWorkers: Int
    let forcedTerminationCount: Int
    let childProcessImportOnlyPassed: Bool
    let subprocessExecutionBlocked: Bool
    let healthCancellationPreserved: Bool
    let oldRegistryDecoded: Bool
    let backupRecoveryPassed: Bool
    let failureMessage: String?
}

@MainActor
enum MCPRuntimeAcceptance {
    static let resultFileName = "mcp-acceptance.json"
    private static let packageName = "@modelcontextprotocol/server-everything"
    private static let packageVersion = "2026.7.4"

    static func run(core: AppRuntimeCore = .shared, fileLayout: RuntimeFileLayout = .default) async {
        let provider = MCPRuntimeProvider.shared
        let service = MCPPackageInstallService(runtime: core.node)
        let registry = MCPServerRegistryStore()
        let controller = provider.controller
        let progressRecorder = MCPAcceptanceProgressRecorder()
        var installation: MCPPackageInstallation?
        var descriptor: MCPServerDescriptor?
        var toolCount = 0
        var harmlessToolSucceeded = false
        var initializeSucceeded = false
        var toolsListSucceeded = false
        var workerStopped = false
        var lazyStartSucceeded = false
        var duplicateStartWasIdempotent = false
        var duplicateStopWasIdempotent = false
        var restartStressPassed = false
        var backgroundStopPassed = false
        var foregroundLazyRestartPassed = false
        var registryPreserved = false
        var maximumConcurrentWorkers = 0
        var forcedTerminationCount = 0
        var childProcessImportOnlyPassed = false
        var subprocessExecutionBlocked = false
        var healthCancellationPreserved = false
        var oldRegistryDecoded = false
        var backupRecoveryPassed = false
        var failureMessage: String?

        do {
            try await core.prepareStorage()
            await provider.loadIfNeeded(startHost: false)
            guard provider.persistentLoadState == .loaded else {
                throw RuntimeCoreError.runtimeFailure(
                    "MCP persistence did not load before acceptance."
                )
            }
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
            await provider.update(installed.descriptor)
            let registryBeforeLifecycle = try await registry.load()

            // No explicit start: schema discovery is the first activation.
            let tools = try await controller.toolDescriptors(serverIDs: [installed.descriptor.id])
            lazyStartSucceeded = true
            initializeSucceeded = true
            toolsListSucceeded = true
            toolCount = tools.count
            guard let echo = tools.first(where: { $0.originalName == "echo" }) else {
                throw RuntimeCoreError.runtimeFailure(
                    "server-everything did not expose its harmless echo tool."
                )
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
            let generationBeforeDuplicateStart = await controller.statuses()[installed.descriptor.id]?.generation
            async let firstStart = controller.ensureRunning(
                installed.descriptor,
                reason: .diagnostics
            )
            async let secondStart = controller.ensureRunning(
                installed.descriptor,
                reason: .diagnostics
            )
            _ = try await (firstStart, secondStart)
            let generationAfterDuplicateStart = await controller.statuses()[installed.descriptor.id]?.generation
            duplicateStartWasIdempotent = generationAfterDuplicateStart
                == generationBeforeDuplicateStart.map { $0 + 1 }

            async let firstStop: Void = controller.stop(serverID: installed.descriptor.id)
            async let secondStop: Void = controller.stop(serverID: installed.descriptor.id)
            _ = await (firstStop, secondStop)
            duplicateStopWasIdempotent =
                await controller.statuses()[installed.descriptor.id]?.state == .stopped

            _ = try await controller.ensureRunning(installed.descriptor, reason: .diagnostics)
            async let firstRestart: Void = controller.restart(installed.descriptor)
            async let secondRestart: Void = controller.restart(installed.descriptor)
            _ = try await (firstRestart, secondRestart)

            for _ in 0..<20 {
                await controller.stop(serverID: installed.descriptor.id)
                _ = try await controller.ensureRunning(installed.descriptor, reason: .diagnostics)
                try await controller.restart(installed.descriptor)
            }
            restartStressPassed = true

            await provider.handleScenePhase(.background)
            backgroundStopPassed =
                await controller.statuses()[installed.descriptor.id]?.state == .stopped
            await provider.handleScenePhase(.active)
            let remainedLazyAfterForeground =
                await controller.statuses()[installed.descriptor.id]?.state == .stopped
            _ = try await controller.toolDescriptors(serverIDs: [installed.descriptor.id])
            let stateAfterLazyRestart =
                await controller.statuses()[installed.descriptor.id]?.state
            foregroundLazyRestartPassed =
                remainedLazyAfterForeground
                && stateAfterLazyRestart == .running

            let policyResult = try await exerciseChildProcessPolicy(
                controller: controller,
                registry: registry
            )
            childProcessImportOnlyPassed = policyResult.importOnlyPassed
            subprocessExecutionBlocked = policyResult.executionBlocked

            let registryResult = try await exerciseRegistryRecovery(using: installed.descriptor)
            oldRegistryDecoded = registryResult.oldDecoded
            backupRecoveryPassed = registryResult.backupRecovered

            let healthTask = Task { try await core.node.healthCheck() }
            healthTask.cancel()
            _ = try? await healthTask.value
            healthCancellationPreserved =
                await core.node.snapshot().state != .appRestartRequired

            await controller.stopAll()
            workerStopped = true
            registryPreserved = try await registry.load() == registryBeforeLifecycle
            let connection = try await core.node.currentConnection()
            let diagnostics = try await connection.decode(
                MCPHostDiagnostics.self,
                path: "/v1/runtime"
            )
            let serverLifecycle = diagnostics.lifecycle.byServer[
                installed.descriptor.id.uuidString.lowercased()
            ]
            maximumConcurrentWorkers = serverLifecycle?.maximumSimultaneousWorkers ?? .max
            forcedTerminationCount = serverLifecycle?.forcedTerminationCount ?? .max
            try await service.commit(installed)
        } catch {
            failureMessage = error.localizedDescription
            if let installation {
                await controller.stop(serverID: installation.descriptor.id)
                do {
                    try await service.rollback(installation)
                } catch {
                    failureMessage = [failureMessage, error.localizedDescription]
                        .compactMap { $0 }
                        .joined(separator: "\n")
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
            && lazyStartSucceeded
            && duplicateStartWasIdempotent
            && duplicateStopWasIdempotent
            && restartStressPassed
            && backgroundStopPassed
            && foregroundLazyRestartPassed
            && registryPreserved
            && maximumConcurrentWorkers <= 1
            && forcedTerminationCount == 0
            && childProcessImportOnlyPassed
            && subprocessExecutionBlocked
            && healthCancellationPreserved
            && oldRegistryDecoded
            && backupRecoveryPassed
            && !clientStdioLoaded
            && !crossSpawnLoaded
            && !childProcessResolved
            && terminalErrorCount == 0

        let result = MCPRuntimeAcceptanceResult(
            schemaVersion: 2,
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
            lazyStartSucceeded: lazyStartSucceeded,
            duplicateStartWasIdempotent: duplicateStartWasIdempotent,
            duplicateStopWasIdempotent: duplicateStopWasIdempotent,
            restartStressPassed: restartStressPassed,
            backgroundStopPassed: backgroundStopPassed,
            foregroundLazyRestartPassed: foregroundLazyRestartPassed,
            registryPreserved: registryPreserved,
            maximumConcurrentWorkers: maximumConcurrentWorkers,
            forcedTerminationCount: forcedTerminationCount,
            childProcessImportOnlyPassed: childProcessImportOnlyPassed,
            subprocessExecutionBlocked: subprocessExecutionBlocked,
            healthCancellationPreserved: healthCancellationPreserved,
            oldRegistryDecoded: oldRegistryDecoded,
            backupRecoveryPassed: backupRecoveryPassed,
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
            preconditionFailure(
                "Could not persist MCP acceptance result: \(error.localizedDescription)"
            )
        }

        if !result.passed {
            try? await Task.sleep(for: .seconds(5))
            preconditionFailure(result.failureMessage ?? "MCP acceptance failed.")
        }
    }

    private static func exerciseChildProcessPolicy(
        controller: MCPRuntimeController,
        registry: MCPServerRegistryStore
    ) async throws -> (importOnlyPassed: Bool, executionBlocked: Bool) {
        let layout = MCPFileLayout.default
        let importDescriptor = try makePolicyFixture(
            layout: layout,
            source: """
            import { spawn } from 'node:child_process';
            import { createInterface } from 'node:readline';
            void spawn;
            createInterface({ input: process.stdin }).on('line', line => {
              const request = JSON.parse(line);
              if (request.method === 'initialize') respond(request.id, { protocolVersion: request.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'import-only', version: '1' } });
              if (request.method === 'tools/list') respond(request.id, { tools: [] });
            });
            function respond(id, result) { process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\\n`); }
            """
        )
        let blockedDescriptor = try makePolicyFixture(
            layout: layout,
            source: """
            import { spawn } from 'node:child_process';
            spawn('blocked');
            """
        )
        defer {
            try? FileManager.default.removeItem(
                at: layout.serverDirectory(id: importDescriptor.id)
            )
            try? FileManager.default.removeItem(
                at: layout.serverDirectory(id: blockedDescriptor.id)
            )
        }
        _ = try await registry.upsert(importDescriptor)
        _ = try await controller.ensureRunning(importDescriptor, reason: .diagnostics)
        await controller.stop(serverID: importDescriptor.id)
        var executionBlocked = false
        do {
            _ = try await controller.ensureRunning(blockedDescriptor, reason: .diagnostics)
            await controller.stop(serverID: blockedDescriptor.id)
        } catch {
            executionBlocked = error.localizedDescription.contains("external process")
                || error.localizedDescription.contains("reachable_external_executable")
        }
        _ = try await registry.remove(id: importDescriptor.id)
        return (true, executionBlocked)
    }

    private static func makePolicyFixture(
        layout: MCPFileLayout,
        source: String
    ) throws -> MCPServerDescriptor {
        let id = UUID()
        let packageRoot = layout.serverDirectory(id: id).appending(
            path: "package",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let entryPoint = packageRoot.appending(path: "server.mjs")
        try Data(source.utf8).write(to: entryPoint, options: .atomic)
        try Data(#"{"name":"policy-fixture","version":"1.0.0","type":"module","main":"server.mjs"}"#.utf8)
            .write(to: packageRoot.appending(path: "package.json"), options: .atomic)
        return MCPServerDescriptor(
            id: id,
            slug: "policy_fixture",
            displayName: "Policy Fixture",
            packageName: "policy-fixture",
            resolvedVersion: "1.0.0",
            entryPoint: entryPoint.path,
            packageRoot: packageRoot.path,
            compatibility: MCPCompatibilityReport(
                verdict: .compatible,
                findings: [],
                runtimeProbePassed: true
            )
        )
    }

    private static func exerciseRegistryRecovery(
        using descriptor: MCPServerDescriptor
    ) async throws -> (oldDecoded: Bool, backupRecovered: Bool) {
        let temporary = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-registry-acceptance-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let layout = MCPFileLayout(root: temporary)
        try layout.prepareIfNeeded()
        let store = MCPServerRegistryStore(fileLayout: layout)
        let missingCopiesDecodedAsEmpty = try await store.load().isEmpty

        var legacyWithAutoStart = descriptor
        legacyWithAutoStart.autoStart = true
        try JSONEncoder.mcp.encode([legacyWithAutoStart]).write(
            to: layout.serverRegistry,
            options: .atomic
        )
        let legacyAutoStartPreserved = try persistentlyEquivalent(
            await store.load(),
            [legacyWithAutoStart]
        )

        var legacyWithoutAutoStart = descriptor
        legacyWithoutAutoStart.autoStart = false
        let encodedLegacy = try JSONEncoder.mcp.encode([legacyWithoutAutoStart])
        guard var legacyObjects = try JSONSerialization.jsonObject(
            with: encodedLegacy
        ) as? [[String: Any]],
              !legacyObjects.isEmpty else {
            throw RuntimeCoreError.runtimeFailure("Could not create legacy MCP registry fixture.")
        }
        legacyObjects[0].removeValue(forKey: "autoStart")
        try JSONSerialization.data(withJSONObject: legacyObjects).write(
            to: layout.serverRegistry,
            options: .atomic
        )
        try? FileManager.default.removeItem(at: layout.serverRegistryBackup)
        let legacyDefaultedSafely = try persistentlyEquivalent(
            await store.load(),
            [legacyWithoutAutoStart]
        )

        try await store.save([descriptor])
        let validBackup = try Data(contentsOf: layout.serverRegistryBackup)
        try Data("{corrupt".utf8).write(to: layout.serverRegistry, options: .atomic)
        try validBackup.write(to: layout.serverRegistryBackup, options: .atomic)
        let primaryRecovered = try persistentlyEquivalent(
            await store.load(),
            [descriptor]
        )
            && (try? JSONDecoder.mcp.decode(
                MCPServerRegistryDocument.self,
                from: Data(contentsOf: layout.serverRegistry)
            )) != nil

        try Data("{corrupt-primary".utf8).write(
            to: layout.serverRegistry,
            options: .atomic
        )
        try Data("corrupt-backup".utf8).write(
            to: layout.serverRegistryBackup,
            options: .atomic
        )
        let bothCorruptFailedClosed: Bool
        do {
            _ = try await store.load()
            bothCorruptFailedClosed = false
        } catch let error as MCPServerRegistryError {
            if case .bothCopiesCorrupt = error {
                bothCorruptFailedClosed = true
            } else {
                bothCorruptFailedClosed = false
            }
        }

        let staleDocument = MCPServerRegistryDocument(
            schemaVersion: MCPServerRegistryDocument.currentSchemaVersion,
            generation: 9,
            servers: [descriptor]
        )
        let uninstallDocument = MCPServerRegistryDocument(
            schemaVersion: MCPServerRegistryDocument.currentSchemaVersion,
            generation: 10,
            servers: []
        )
        try JSONEncoder.mcp.encode(uninstallDocument).write(
            to: layout.serverRegistry,
            options: .atomic
        )
        try JSONEncoder.mcp.encode(staleDocument).write(
            to: layout.serverRegistryBackup,
            options: .atomic
        )
        let uninstallWasNotResurrected = try await store.load().isEmpty
        let repairedBackup = try JSONDecoder.mcp.decode(
            MCPServerRegistryDocument.self,
            from: Data(contentsOf: layout.serverRegistryBackup)
        )
        let backupContainsIntentionalEmpty =
            repairedBackup.generation == uninstallDocument.generation
            && repairedBackup.servers.isEmpty

        return (
            missingCopiesDecodedAsEmpty
                && legacyAutoStartPreserved
                && legacyDefaultedSafely,
            primaryRecovered
                && bothCorruptFailedClosed
                && uninstallWasNotResurrected
                && backupContainsIntentionalEmpty
        )
    }

    private static func persistentlyEquivalent(
        _ lhs: [MCPServerDescriptor],
        _ rhs: [MCPServerDescriptor]
    ) throws -> Bool {
        try JSONEncoder.mcp.encode(lhs) == JSONEncoder.mcp.encode(rhs)
    }
}
#endif
