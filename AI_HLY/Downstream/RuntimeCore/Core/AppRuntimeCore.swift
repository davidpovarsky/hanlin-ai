import Foundation

actor AppRuntimeCore {
    static let shared = AppRuntimeCore()

    nonisolated let node: NodeRuntimeService
    nonisolated let python: PythonRuntimeService
    nonisolated let typeScript: TypeScriptRuntimeService
    nonisolated let nodePackages: NodePackageManager
    nonisolated let javaScriptCore: JavaScriptCoreRuntimeService
    nonisolated let shell: ShellRuntimeService
    nonisolated let environment: RuntimeEnvironmentStore
    nonisolated let pythonPackages: PythonPackageManager
    nonisolated let diagnostics: RuntimeDiagnostics
    nonisolated let lifecycle: LifecycleExecutionBroker

    private let fileLayout: RuntimeFileLayout

    private init(fileLayout: RuntimeFileLayout = .default) {
        self.fileLayout = fileLayout
        let python = PythonRuntimeService(fileLayout: fileLayout)
        let node = NodeRuntimeService(fileLayout: fileLayout)
        let typeScript = TypeScriptRuntimeService(node: node)
        let shell = ShellRuntimeService(fileLayout: fileLayout)
        let lifecycle = LifecycleExecutionBroker(node: node, typeScript: typeScript, python: python, shell: shell, fileLayout: fileLayout)
        self.node = node
        self.typeScript = typeScript
        nodePackages = NodePackageManager(node: node, lifecycle: lifecycle)
        self.python = python
        javaScriptCore = JavaScriptCoreRuntimeService()
        self.shell = shell
        environment = RuntimeEnvironmentStore(fileLayout: fileLayout)
        pythonPackages = PythonPackageManager(fileLayout: fileLayout, python: python)
        diagnostics = RuntimeDiagnostics()
        self.lifecycle = lifecycle
    }

    func prepareStorage() throws {
        try fileLayout.prepareIfNeeded()
    }

    func snapshots() async -> [RuntimeSnapshot] {
        let nodeSnapshot = await node.snapshot()
        let pythonSnapshot = await python.snapshot()
        let javaScriptCoreSnapshot = await javaScriptCore.snapshot()
        let shellSnapshot = await shell.snapshot()
        let tsState: RuntimeOperationalState = RuntimeAvailabilityStore.shared.isAvailable(.typeScript) ? nodeSnapshot.state : .stopped
        let tsSnapshot = RuntimeSnapshot(
            kind: .typeScript,
            state: tsState,
            version: "6.0.3",
            source: "typescript npm package",
            lastHealthCheck: nodeSnapshot.lastHealthCheck,
            lastErrorCode: nodeSnapshot.lastErrorCode,
            storageBytes: nil,
            cacheBytes: nil,
            activeExecutionCount: nodeSnapshot.activeExecutionCount,
            packageCount: nil
        )
        return [nodeSnapshot, pythonSnapshot, javaScriptCoreSnapshot, shellSnapshot, tsSnapshot]
    }

    func start(_ kind: RuntimeKind) async throws -> RuntimeSnapshot {
        switch kind {
        case .node:
            let s = try await node.healthCheck()
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .node)
            return s
        case .typeScript:
            _ = try await node.healthCheck()
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .node)
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .typeScript)
            let s = await node.snapshot()
            return RuntimeSnapshot(kind: .typeScript, state: s.state, version: "6.0.3", source: "typescript npm package", lastHealthCheck: s.lastHealthCheck, lastErrorCode: s.lastErrorCode, storageBytes: nil, cacheBytes: nil, activeExecutionCount: s.activeExecutionCount, packageCount: nil)
        case .localPython:
            let s = try await python.prepare()
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .localPython)
            return s
        case .javaScriptCore:
            let s = try await javaScriptCore.healthCheck()
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .javaScriptCore)
            return s
        case .shell:
            let s = try await shell.healthCheck()
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .shell)
            return s
        }
    }

    func stop(_ kind: RuntimeKind) async throws -> RuntimeSnapshot {
        switch kind {
        case .node:
            let s = await node.stop()
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .node)
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .typeScript)
            return s
        case .typeScript:
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .typeScript)
            let s = await node.snapshot()
            return RuntimeSnapshot(kind: .typeScript, state: .stopped, version: "6.0.3", source: "typescript npm package", lastHealthCheck: s.lastHealthCheck, lastErrorCode: s.lastErrorCode, storageBytes: nil, cacheBytes: nil, activeExecutionCount: s.activeExecutionCount, packageCount: nil)
        case .localPython:
            let s = await python.stop()
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .localPython)
            return s
        case .javaScriptCore:
            let s = await javaScriptCore.stop()
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .javaScriptCore)
            return s
        case .shell:
            let s = await shell.stop()
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .shell)
            return s
        }
    }

    func ensureStarted(_ kind: RuntimeKind) async throws -> RuntimeSnapshot {
        switch kind {
        case .node:
            let s = await node.snapshot()
            if s.state == .ready || s.state == .executing {
                return s
            }
            return try await node.healthCheck()
        case .typeScript:
            _ = try await ensureStarted(.node)
            let s = await node.snapshot()
            return RuntimeSnapshot(kind: .typeScript, state: s.state, version: "6.0.3", source: "typescript npm package", lastHealthCheck: s.lastHealthCheck, lastErrorCode: s.lastErrorCode, storageBytes: nil, cacheBytes: nil, activeExecutionCount: s.activeExecutionCount, packageCount: nil)
        case .localPython:
            let s = await python.snapshot()
            if s.state == .ready || s.state == .executing {
                return s
            }
            return try await python.prepare()
        case .javaScriptCore:
            let s = await javaScriptCore.snapshot()
            if s.state == .ready || s.state == .executing {
                return s
            }
            return try await javaScriptCore.healthCheck()
        case .shell:
            let s = await shell.snapshot()
            if s.state == .ready || s.state == .executing {
                return s
            }
            return try await shell.healthCheck()
        }
    }

    func handleForegroundIfLaunched() async {
        try? fileLayout.prepareIfNeeded()
        _ = try? await node.healthCheckIfLaunched()
    }

    func clearReproducibleCaches() throws {
        for url in [fileLayout.npmCache, fileLayout.pypiCache, fileLayout.typeScriptCache, fileLayout.temporary] {
            let validated = try fileLayout.validatedDescendant(url, of: fileLayout.root, allowRoot: false)
            if FileManager.default.fileExists(atPath: validated.path) { try FileManager.default.removeItem(at: validated) }
            try FileManager.default.createDirectory(at: validated, withIntermediateDirectories: true)
        }
    }
}
