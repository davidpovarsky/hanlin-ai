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
    nonisolated let jobs: RuntimeJobStore

    private let fileLayout: RuntimeFileLayout

    private init(fileLayout: RuntimeFileLayout = .default) {
        self.fileLayout = fileLayout
        let environment = RuntimeEnvironmentStore(fileLayout: fileLayout)
        self.environment = environment
        let jobs = RuntimeJobStore(fileLayout: fileLayout)
        self.jobs = jobs
        let python = PythonRuntimeService(fileLayout: fileLayout, jobs: jobs, environment: environment)
        let shell = ShellRuntimeService(fileLayout: fileLayout, jobs: jobs, environment: environment)
        let node = NodeRuntimeService(fileLayout: fileLayout, environment: environment, python: python, shell: shell)
        let typeScript = TypeScriptRuntimeService(node: node)
        let lifecycle = LifecycleExecutionBroker(node: node, typeScript: typeScript, python: python, shell: shell, fileLayout: fileLayout)
        self.node = node
        self.typeScript = typeScript
        nodePackages = NodePackageManager(node: node, lifecycle: lifecycle)
        self.python = python
        javaScriptCore = JavaScriptCoreRuntimeService(environment: environment, fileLayout: fileLayout, jobs: jobs)
        self.shell = shell
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
        let tsSnapshot = await typeScript.snapshot()
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
            let s = try await typeScript.healthCheck()
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .node)
            RuntimeAvailabilityStore.shared.setAvailable(true, for: .typeScript)
            return s
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
            // A running embedded Node cannot be unloaded. Preserve its availability.
            return await node.stop()
        case .typeScript:
            RuntimeAvailabilityStore.shared.setAvailable(false, for: .typeScript)
            return await typeScript.stop()
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
            let s = await typeScript.snapshot()
            if s.state == .ready || s.state == .executing { return s }
            return try await typeScript.healthCheck()
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
