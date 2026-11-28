import Foundation
import HanlinPlatformContracts

public enum HanlinMiniAppVisibilityError: Error, Equatable, Sendable {
    case invalidState
}

/// One marker per hidden canonical ID lets the existing file transfer preserve
/// both products' choices without replacing a destination preference list.
/// The schema marker is committed after the legacy IDs have been copied.
public final class HanlinMiniAppVisibilityStore: @unchecked Sendable {
    private let root: URL
    private let hiddenRoot: URL
    private let versionURL: URL
    private static let marker = Data("hidden-v1\n".utf8)
    private static let version = Data("1\n".utf8)

    public init(dataRoot: URL, legacyHiddenIDs: Set<HanlinAppID>) throws {
        let dataRoot = dataRoot.resolvingSymlinksInPath().standardizedFileURL
        root = dataRoot.appending(path: ".catalog-state", directoryHint: .isDirectory)
        hiddenRoot = root.appending(path: "hidden", directoryHint: .isDirectory)
        versionURL = root.appending(path: "version")
        try HanlinStoreFileAccess.withExclusiveAccess {
            try Self.directory(dataRoot)
            try Self.directory(root)
            try Self.directory(hiddenRoot)
            if FileManager.default.fileExists(atPath: versionURL.path) {
                try validateVersion()
                _ = try hiddenIDs()
            } else {
                // A partial first migration is resumed without deleting markers.
                _ = try readIDs()
                for id in legacyHiddenIDs { try Self.marker.write(to: markerURL(id), options: .atomic) }
                try Self.version.write(to: versionURL, options: .atomic)
            }
        }
    }

    public func hiddenIDs() throws -> Set<HanlinAppID> {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try validateVersion()
            return try readIDs()
        }
    }

    public func setHidden(_ hidden: Bool, appID: HanlinAppID) throws {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try validateVersion()
            _ = try readIDs()
            let path = try markerURL(appID)
            if hidden {
                try Self.marker.write(to: path, options: .atomic)
            } else if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
        }
    }

    private func markerURL(_ appID: HanlinAppID) throws -> URL {
        let value = appID.rawValue
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"),
              !value.contains("\\"), !value.contains("\0") else { throw HanlinMiniAppVisibilityError.invalidState }
        return hiddenRoot.appending(path: value)
    }

    private func validateVersion() throws {
        try Self.requireDirectory(root)
        try Self.requireDirectory(hiddenRoot)
        let values = try versionURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              try Data(contentsOf: versionURL) == Self.version else { throw HanlinMiniAppVisibilityError.invalidState }
    }

    private func readIDs() throws -> Set<HanlinAppID> {
        try Self.requireDirectory(hiddenRoot)
        let files = try FileManager.default.contentsOfDirectory(at: hiddenRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        var ids = Set<HanlinAppID>()
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let id = HanlinAppID(rawValue: file.lastPathComponent),
                  try Data(contentsOf: file) == Self.marker else { throw HanlinMiniAppVisibilityError.invalidState }
            ids.insert(id)
        }
        return ids
    }

    private static func directory(_ url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try requireDirectory(url)
    }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw HanlinMiniAppVisibilityError.invalidState }
    }
}
