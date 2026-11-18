import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Versioned product ownership inside the existing trusted App Group container.
/// This selects storage; it never copies, migrates, or falls back to another product's data.
public enum SplitAppStorageLayout {
    public static let version = 1
    public static let miniAppsBundleIdentifier = "com.itorah.hanlinminiapps"

    public enum LayoutError: Error, Equatable {
        case unknownProduct
        case appGroupUnavailable
        case invalidNamespace
    }

    public static func extensionStoreRoot(
        trustedBundleIdentifier: String?, appGroupContainer: URL?
    ) throws -> URL {
        guard trustedBundleIdentifier == "com.itorah.chavrusachat"
                || trustedBundleIdentifier == miniAppsBundleIdentifier else {
            throw LayoutError.unknownProduct
        }
        guard let appGroupContainer else { throw LayoutError.appGroupUnavailable }
        let container = appGroupContainer.resolvingSymlinksInPath().standardizedFileURL
        guard trustedBundleIdentifier == miniAppsBundleIdentifier else {
            return container.appending(path: "ScriptingExtensions", directoryHint: .isDirectory)
        }
        return try checkedRoot(container: container, components: ["HanlinMiniApps", "v1", "ScriptingExtensions"])
    }

    public static func transportRoot(appGroupContainer: URL?) throws -> URL {
        guard let appGroupContainer else { throw LayoutError.appGroupUnavailable }
        return try checkedRoot(container: appGroupContainer.resolvingSymlinksInPath().standardizedFileURL,
                               components: ["HanlinSplit", "v1"])
    }

    public static func productTransferRoot(appGroupContainer: URL?) throws -> URL {
        guard let appGroupContainer else { throw LayoutError.appGroupUnavailable }
        return try checkedRoot(container: appGroupContainer.resolvingSymlinksInPath().standardizedFileURL,
                               components: ["HanlinSplit", "v1", "ProductTransfer"])
    }

    private static func checkedRoot(container: URL, components: [String]) throws -> URL {
        var candidate = container
        // Check every fixed ancestor before the existing store canonicalizes its parent.
        // A Finder alias is a regular file and is rejected along with symlinks/non-directories.
        for component in components {
            candidate.append(path: component, directoryHint: .isDirectory)
#if canImport(Darwin)
            var info = stat()
            if Darwin.lstat(candidate.path(percentEncoded: false), &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFDIR else { throw LayoutError.invalidNamespace }
            } else if errno != ENOENT {
                throw LayoutError.invalidNamespace
            }
#else
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: candidate.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory,
                      candidate.resolvingSymlinksInPath().standardizedFileURL == candidate.standardizedFileURL else {
                    throw LayoutError.invalidNamespace
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // Missing fixed directories are created by the existing store on first write.
            }
#endif
        }
        return candidate
    }
}
