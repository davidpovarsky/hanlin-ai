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
        return [nodeSnapshot, pythonSnapshot, javaScriptCoreSnapshot, shellSnapshot]
    }

    func handleForeground() async {
        try? fileLayout.prepareIfNeeded()
        _ = try? await node.healthCheck()
    }

    func clearReproducibleCaches() throws {
        for url in [fileLayout.npmCache, fileLayout.pypiCache, fileLayout.typeScriptCache, fileLayout.temporary] {
            let validated = try fileLayout.validatedDescendant(url, of: fileLayout.root, allowRoot: false)
            if FileManager.default.fileExists(atPath: validated.path) { try FileManager.default.removeItem(at: validated) }
            try FileManager.default.createDirectory(at: validated, withIntermediateDirectories: true)
        }
    }
}
