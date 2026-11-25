import Foundation

/// Immutable source namespaces inside the original runtime's one application root.
/// Unique file paths are original NativeScript loader/cache identities. We never
/// rewrite application JavaScript or manufacture a replacement module evaluator.
@MainActor
struct HanlinNativeScriptWindowPackage {
    let root: URL
    let packageID: String
    let environmentJSON: String
    let loaderConfigurationJSON: String
    let styleSheetPath: String?

    static func stage(
        source: URL, hostRoot: URL, windowID: String,
        environment: [String: String], sharedRuntime: URL
    ) throws -> Self {
        let manager = FileManager.default
        let source = try HanlinNativeScriptSession.validatePreparedApplication(source).resolvingSymlinksInPath()
        let root = hostRoot.appendingPathComponent("windows", isDirectory: true)
            .appendingPathComponent(windowID, isDirectory: true)
        try manager.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !manager.fileExists(atPath: root.path) else { throw failure("The window source namespace already exists.") }

        // Imported package trees cannot acquire an external file alias here.
        // Previously managed shared-runtime links are omitted and rebuilt below.
        let canonicalShared = sharedRuntime.resolvingSymlinksInPath()
        func copy(_ from: URL, to: URL, ancestors: Set<String>) throws {
            let values = try from.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true {
                let resolved = from.resolvingSymlinksInPath()
                if contains(canonicalShared, resolved) { return }
                guard contains(source, resolved), !ancestors.contains(resolved.path) else {
                    throw failure("A package link escapes its source namespace or forms a cycle.")
                }
                try copy(resolved, to: to, ancestors: ancestors)
            } else if values.isDirectory == true {
                guard !ancestors.contains(from.path) else { throw failure("A package directory forms a cycle.") }
                try manager.createDirectory(at: to, withIntermediateDirectories: false)
                var parents = ancestors
                parents.insert(from.path)
                for child in try manager.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) {
                    try copy(child, to: to.appendingPathComponent(child.lastPathComponent), ancestors: parents)
                }
            } else if values.isRegularFile == true {
                try manager.copyItem(at: from, to: to)
            } else {
                throw failure("The package contains a non-regular source file.")
            }
        }
        do {
            try copy(source, to: root, ancestors: [])
            _ = try HanlinNativeScriptSharedModuleLinks.prepare(sharedRuntime: sharedRuntime, applicationRoot: root)
            let manifest = try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("package.json"))) as? [String: Any]
            let packageID = environment["HANLIN_APP_ID"] ?? manifest?["name"] as? String ?? windowID
            var scopes: [String: [String: String]] = [:]
            func relativeToHost(_ file: URL) throws -> String {
                let normalized = file.standardizedFileURL
                guard contains(hostRoot.standardizedFileURL, normalized) else {
                    throw failure("An import-map target escapes the runtime application root.")
                }
                return String(normalized.path.dropFirst(hostRoot.standardizedFileURL.path.count))
            }
            // NativeScript's original import-map scopes match canonical absolute
            // referrer paths; map targets beginning "/" are application-relative.
            // Nested dependency scopes inherit their parent's map in the engine.
            func mapDependencies(in directory: URL) throws {
                let modules = directory.appendingPathComponent("node_modules", isDirectory: true)
                var entries: [String: String] = [:]
                if directory == root {
                    entries["~/"] = try relativeToHost(root) + "/"
                }
                if (try? modules.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                   (try? modules.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true {
                    func addPackage(_ package: URL, name: String) throws {
                        let values = try package.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                        // Original host libraries remain one canonical upstream copy.
                        guard values.isSymbolicLink != true, values.isDirectory == true else { return }
                        let metadataURL = package.appendingPathComponent("package.json")
                        let metadata = (try? Data(contentsOf: metadataURL))
                            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                        let target = try relativeToHost(package)
                        if let main = metadata?["module"] as? String ?? metadata?["main"] as? String {
                            let entry = package.appendingPathComponent(main).standardizedFileURL
                            guard contains(package.standardizedFileURL, entry) else {
                                throw failure("A dependency entry escapes its package namespace.")
                            }
                            entries[name] = try relativeToHost(entry)
                        } else {
                            entries[name] = target
                        }
                        entries[name + "/"] = target + "/"
                    }
                    for package in try manager.contentsOfDirectory(at: modules, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles]) {
                        if package.lastPathComponent.hasPrefix("@") {
                            guard (try? package.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { continue }
                            for child in try manager.contentsOfDirectory(at: package, includingPropertiesForKeys: nil) {
                                try addPackage(child, name: package.lastPathComponent + "/" + child.lastPathComponent)
                            }
                        } else { try addPackage(package, name: package.lastPathComponent) }
                    }
                }
                if !entries.isEmpty {
                    scopes[directory.resolvingSymlinksInPath().path + "/"] = entries
                }
                for child in try manager.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                    let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if values.isDirectory == true && values.isSymbolicLink != true { try mapDependencies(in: child) }
                }
            }
            try mapDependencies(in: root)
            let configuration: [String: Any] = [
                "entrypoint": root.appendingPathComponent("bundle.mjs").path,
                "scopes": scopes,
            ]
            let css = root.appendingPathComponent("app.css")
            return Self(
                root: root, packageID: packageID,
                environmentJSON: try json(environment),
                loaderConfigurationJSON: try json(configuration),
                styleSheetPath: manager.fileExists(atPath: css.path) ? css.path : nil
            )
        } catch {
            // Only our freshly allocated UUID namespace is removed on admission failure.
            try? manager.removeItem(at: root)
            throw error
        }
    }

    static func makeHostRoot(sharedRuntime: URL) throws -> URL {
        let manager = FileManager.default
        let cache = try manager.url(for: .cachesDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let root = cache.appendingPathComponent("HanlinNativeScriptWindows", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("host", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let manifest: [String: Any] = [
                "name": "hanlin-native-window-host", "private": true, "type": "module",
                "main": "bundle.mjs", "hanlinRuntime": "hanlin-nativescript",
                "hanlinNativeScript": ["runtimeVersion": HanlinNativeScriptHostVersions.runtimeVersion,
                                      "plugins": [:] as [String: String]],
                "dependencies": ["@nativescript/core": HanlinNativeScriptHostVersions.coreVersion],
            ]
            try Data(json(manifest).utf8).write(to: root.appendingPathComponent("package.json"), options: .atomic)
            try manager.copyItem(at: sharedRuntime.appendingPathComponent("@hanlin/window-factory/host.mjs"),
                                 to: root.appendingPathComponent("bundle.mjs"))
            return root.resolvingSymlinksInPath()
        } catch {
            try? manager.removeItem(at: root.deletingLastPathComponent())
            throw error
        }
    }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }
    private static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "HanlinNativeScript.WindowPackage", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
