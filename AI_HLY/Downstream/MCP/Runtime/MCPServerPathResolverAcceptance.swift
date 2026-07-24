import Foundation

#if targetEnvironment(simulator)
enum MCPServerPathResolverAcceptance {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-mcp-path-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = MCPFileLayout(root: root)
        try layout.prepareIfNeeded()
        let resolver = MCPServerPathResolver(fileLayout: layout)

        let newDescriptor = try makeInstalledDescriptor(
            layout: layout,
            packageName: "new-relative",
            relativePath: "dist/index.js"
        )
        var relativeDescriptor = newDescriptor
        relativeDescriptor.entryPointRelativePath = "dist/index.js"
        let relativePaths = try resolver.resolve(relativeDescriptor)
        try require(
            relativePaths.entryPointRelativePath == "dist/index.js"
                && !relativePaths.requiredMigration,
            "A new relative descriptor did not resolve idempotently."
        )

        let nestedDescriptor = try makeInstalledDescriptor(
            layout: layout,
            packageName: "legacy-absolute",
            relativePath: "build/index.js",
            nestedPackage: true
        )
        let nestedPaths = try resolver.resolve(nestedDescriptor)
        try require(
            nestedPaths.packageRoot == layout.serverDirectory(id: nestedDescriptor.id)
                && nestedPaths.entryPointRelativePath == "build/index.js"
                && nestedPaths.requiredMigration,
            "The legacy nested package layout did not migrate."
        )

        let oldContainerDescriptor = try makeInstalledDescriptor(
            layout: layout,
            packageName: "old-container",
            relativePath: "dist/index.cjs",
            persistedRoot: "/private/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/HanlinRuntime/v1/packages/mcp/{id}",
            persistedEntryPoint: "/private/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/HanlinRuntime/v1/packages/mcp/{id}/dist/index.cjs"
        )
        let oldContainerPaths = try resolver.resolve(oldContainerDescriptor)
        try require(
            oldContainerPaths.entryPointRelativePath == "dist/index.cjs"
                && oldContainerPaths.requiredMigration,
            "An old container UUID was not migrated."
        )

        var optionFallbackDescriptor = newDescriptor
        optionFallbackDescriptor.entryPointRelativePath = nil
        optionFallbackDescriptor.entryPoint = "/obsolete/location/server.js"
        optionFallbackDescriptor.binName = "fixture"
        optionFallbackDescriptor.entryPointOptions = [
            MCPEntryPointOption(
                binName: "fixture",
                entryPoint: "./dist/index.js"
            )
        ]
        let optionFallbackPaths = try resolver.resolve(optionFallbackDescriptor)
        try require(
            optionFallbackPaths.entryPointRelativePath == "dist/index.js",
            "A relative entry-point option did not repair an obsolete absolute entry."
        )

        let stagingDescriptor = try makeInstalledDescriptor(
            layout: layout,
            packageName: "staging-root",
            relativePath: "dist/index.js",
            persistedRoot: root.appending(path: "staging/operation/package").path,
            persistedEntryPoint: root.appending(path: "staging/operation/package/dist/index.js").path
        )
        try expect(.packageRootInvalid) {
            _ = try resolver.resolve(stagingDescriptor)
        }

        let otherID = UUID()
        let otherRoot = layout.serverDirectory(id: otherID)
        let wrongServerDescriptor = try makeInstalledDescriptor(
            layout: layout,
            packageName: "wrong-server",
            relativePath: "dist/index.js",
            persistedRoot: otherRoot.path,
            persistedEntryPoint: otherRoot.appending(path: "dist/index.js").path
        )
        try expect(.packageRootInvalid) {
            _ = try resolver.resolve(wrongServerDescriptor)
        }

        var traversalDescriptor = newDescriptor
        traversalDescriptor.entryPointRelativePath = "../outside.js"
        try expect(.entryPointInvalid) {
            _ = try resolver.resolve(traversalDescriptor)
        }

        var absoluteRelativeDescriptor = newDescriptor
        absoluteRelativeDescriptor.entryPointRelativePath = "/outside/index.js"
        try expect(.entryPointInvalid) {
            _ = try resolver.resolve(absoluteRelativeDescriptor)
        }

        let outside = root.appending(path: "outside.js")
        try Data("export {};".utf8).write(to: outside)
        let symlink = layout.serverDirectory(id: newDescriptor.id).appending(path: "escape.js")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        var symlinkDescriptor = newDescriptor
        symlinkDescriptor.entryPointRelativePath = "escape.js"
        try expect(.symbolicLinkEscape) {
            _ = try resolver.resolve(symlinkDescriptor)
        }

        let missingDirectoryDescriptor = descriptor(
            id: UUID(),
            packageName: "missing-directory",
            packageRoot: root.appending(path: "packages/mcp/missing").path,
            entryPoint: root.appending(path: "packages/mcp/missing/index.js").path
        )
        try expect(.packageDirectoryMissing) {
            _ = try resolver.resolve(missingDirectoryDescriptor)
        }

        var missingEntryDescriptor = newDescriptor
        missingEntryDescriptor.entryPointRelativePath = "dist/missing.js"
        try expect(.entryPointMissing) {
            _ = try resolver.resolve(missingEntryDescriptor)
        }

        var settingsDescriptor = oldContainerDescriptor
        settingsDescriptor.environment = [
            MCPEnvironmentVariable(
                name: "TOKEN",
                value: nil,
                secretReference: "keychain-reference"
            )
        ]
        settingsDescriptor.arguments = ["--mode", "safe"]
        settingsDescriptor.isGloballyEnabled = false
        settingsDescriptor.isEnabledForNewChats = false
        settingsDescriptor.autoStart = true
        let settingsPaths = try resolver.resolve(settingsDescriptor)
        let migratedSettings = resolver.migratedDescriptor(
            settingsDescriptor,
            paths: settingsPaths
        )
        try require(
            migratedSettings.id == settingsDescriptor.id
                && migratedSettings.installedAt == settingsDescriptor.installedAt
                && migratedSettings.environment == settingsDescriptor.environment
                && migratedSettings.arguments == settingsDescriptor.arguments
                && migratedSettings.isGloballyEnabled == settingsDescriptor.isGloballyEnabled
                && migratedSettings.isEnabledForNewChats == settingsDescriptor.isEnabledForNewChats
                && migratedSettings.autoStart == settingsDescriptor.autoStart,
            "Path migration changed persistent server settings."
        )
        let secondPaths = try resolver.resolve(migratedSettings)
        try require(!secondPaths.requiredMigration, "Path migration was not idempotent.")

        var uppercaseDescriptor = newDescriptor
        uppercaseDescriptor.entryPointRelativePath = nil
        uppercaseDescriptor.packageRoot = newDescriptor.packageRoot.replacingOccurrences(
            of: newDescriptor.id.uuidString.lowercased(),
            with: newDescriptor.id.uuidString.uppercased()
        )
        uppercaseDescriptor.entryPoint = newDescriptor.entryPoint.replacingOccurrences(
            of: newDescriptor.id.uuidString.lowercased(),
            with: newDescriptor.id.uuidString.uppercased()
        )
        let uppercasePaths = try resolver.resolve(uppercaseDescriptor)
        try require(
            uppercasePaths.entryPointRelativePath == "dist/index.js",
            "An uppercase persisted UUID path did not migrate."
        )

        let sequentialDescriptor = try makeInstalledDescriptor(
            layout: layout,
            packageName: "@modelcontextprotocol/server-sequential-thinking",
            version: "2026.7.4",
            relativePath: "dist/index.js",
            persistedRoot: "/private/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/HanlinMCP/servers/{id}/package",
            persistedEntryPoint: "/private/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/HanlinMCP/servers/{id}/package/dist/index.js"
        )
        let sequentialPaths = try resolver.resolve(sequentialDescriptor)
        let migratedSequential = resolver.migratedDescriptor(
            sequentialDescriptor,
            paths: sequentialPaths
        )
        let store = MCPServerRegistryStore(fileLayout: layout)
        let selectionStore = MCPChatSelectionStore(fileLayout: layout)
        let chatID = UUID()
        try await selectionStore.setSelection(
            [sequentialDescriptor.id],
            chatID: chatID
        )
        _ = try await store.upsert(migratedSequential)
        let persistedSequential = try await store.load().first {
            $0.id == sequentialDescriptor.id
        }
        try require(
            persistedSequential?.entryPointRelativePath == "dist/index.js"
                && persistedSequential?.packageRoot
                    == layout.serverDirectory(id: sequentialDescriptor.id).path,
            "The sequential-thinking migration was not persisted canonically."
        )
        let preservedSelection = try await selectionStore.selection(chatID: chatID)
        try require(
            preservedSelection == Set([sequentialDescriptor.id]),
            "Path migration changed the chat selection."
        )
    }

    private static func makeInstalledDescriptor(
        layout: MCPFileLayout,
        packageName: String,
        version: String = "1.0.0",
        relativePath: String,
        nestedPackage: Bool = false,
        persistedRoot: String? = nil,
        persistedEntryPoint: String? = nil
    ) throws -> MCPServerDescriptor {
        let id = UUID()
        let serverRoot = layout.serverDirectory(id: id)
        let packageRoot = nestedPackage
            ? serverRoot.appending(path: "package", directoryHint: .isDirectory)
            : serverRoot
        let entryPoint = packageRoot.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: entryPoint.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("export {};".utf8).write(to: entryPoint)
        try Data(
            #"{"name":"fixture","version":"1.0.0","type":"module","main":"dist/index.js"}"#.utf8
        ).write(to: packageRoot.appending(path: "package.json"))
        let storedRoot = persistedRoot?
            .replacingOccurrences(of: "{id}", with: id.uuidString.lowercased())
            ?? packageRoot.path
        let storedEntry = persistedEntryPoint?
            .replacingOccurrences(of: "{id}", with: id.uuidString.lowercased())
            ?? entryPoint.path
        return descriptor(
            id: id,
            packageName: packageName,
            version: version,
            packageRoot: storedRoot,
            entryPoint: storedEntry
        )
    }

    private static func descriptor(
        id: UUID,
        packageName: String,
        version: String = "1.0.0",
        packageRoot: String,
        entryPoint: String
    ) -> MCPServerDescriptor {
        MCPServerDescriptor(
            id: id,
            slug: MCPToolNameCodec.slug(packageName),
            displayName: packageName,
            packageName: packageName,
            resolvedVersion: version,
            entryPoint: entryPoint,
            packageRoot: packageRoot,
            compatibility: MCPCompatibilityReport(
                verdict: .compatible,
                findings: [],
                runtimeProbePassed: true
            )
        )
    }

    private static func expect(
        _ expected: MCPServerPathResolutionError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            throw RuntimeCoreError.runtimeFailure(
                "Expected path error \(expected), but resolution succeeded."
            )
        } catch let error as MCPServerPathResolutionError {
            try require(error == expected, "Received path error \(error), expected \(expected).")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RuntimeCoreError.runtimeFailure(message) }
    }
}
#endif
