import Foundation

/// Merges original shared modules with a package's own npm tree without replacing
/// its files or duplicating the original NativeScript Core.
struct HanlinNativeScriptSharedModuleLinks {
    static func prepare(sharedRuntime: URL, applicationRoot: URL) throws -> Set<URL> {
        let manager = FileManager.default
        var links = Set<URL>()

        func refreshManagedLink(_ target: URL, to source: URL) throws -> Bool {
            guard let destination = try? manager.destinationOfSymbolicLink(atPath: target.path) else { return false }
            let existing = URL(fileURLWithPath: destination, relativeTo: target.deletingLastPathComponent()).standardizedFileURL.path
            let current = source.standardizedFileURL.path
            let shared = sharedRuntime.standardizedFileURL.path
            let suffix = current == shared ? "" : String(current.dropFirst(shared.count))
            let oldHostLink = sharedRuntime.lastPathComponent == "NativeScriptSharedRuntime" &&
                existing.hasSuffix("/NativeScriptSharedRuntime" + suffix)
            guard existing == current || oldHostLink else { return false }
            if existing != current {
                // An app update can change the resource bundle URL after a previous
                // process ended without cleanup. Refresh only our known host links.
                try manager.removeItem(at: target)
                try manager.createSymbolicLink(at: target, withDestinationURL: source)
            }
            links.insert(target)
            return true
        }

        func merge(_ sourceRoot: URL, into targetRoot: URL) throws {
            for source in try manager.contentsOfDirectory(at: sourceRoot,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                let target = targetRoot.appending(path: source.lastPathComponent)
                if try refreshManagedLink(target, to: source) { continue }
                var directory: ObjCBool = false
                if manager.fileExists(atPath: target.path, isDirectory: &directory) {
                    if let existing = try? manager.destinationOfSymbolicLink(atPath: target.path),
                       URL(fileURLWithPath: existing, relativeTo: target.deletingLastPathComponent()).standardizedFileURL.path == source.standardizedFileURL.path {
                        links.insert(target)
                    } else if source.lastPathComponent.hasPrefix("@"), directory.boolValue {
                        // A scope may already contain a user plugin. Add only its missing siblings.
                        try merge(source, into: target)
                    }
                    continue
                }
                if (try? manager.destinationOfSymbolicLink(atPath: target.path)) != nil {
                    // Preserve even an existing broken user link; ordinary import diagnostics
                    // will identify it instead of silently overwriting the package.
                    continue
                }
                try manager.createSymbolicLink(at: target, withDestinationURL: source)
                links.insert(target)
            }
        }

        try merge(sharedRuntime, into: applicationRoot)
        let modules = applicationRoot.appending(path: "node_modules", directoryHint: .isDirectory)
        if try refreshManagedLink(modules, to: sharedRuntime) { return links }
        var directory: ObjCBool = false
        if manager.fileExists(atPath: modules.path, isDirectory: &directory), directory.boolValue {
            if let existing = try? manager.destinationOfSymbolicLink(atPath: modules.path),
               URL(fileURLWithPath: existing, relativeTo: modules.deletingLastPathComponent()).standardizedFileURL.path == sharedRuntime.standardizedFileURL.path {
                links.insert(modules)
            } else {
                try merge(sharedRuntime, into: modules)
            }
        } else if (try? manager.destinationOfSymbolicLink(atPath: modules.path)) == nil {
            try manager.createSymbolicLink(at: modules, withDestinationURL: sharedRuntime)
            links.insert(modules)
        }
        return links
    }
}
