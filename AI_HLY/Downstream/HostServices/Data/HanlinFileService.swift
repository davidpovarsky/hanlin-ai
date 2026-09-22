import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Additional file service utilities for Mini App engines.
/// The primary file operations are on `HanlinHostServicesBroker`; this
/// provides path validation and physical URL resolution helpers.
enum HanlinFileService {

    // MARK: - Path Validation

    /// Validate that a virtual path is safe (no traversal, no symlinks).
    /// Throws `HanlinHostServiceError.pathOutOfScope` if the path is invalid.
    static func validatePath(_ path: String) throws {
        guard !path.isEmpty else {
            throw HanlinHostServiceError.pathOutOfScope("empty path")
        }

        // Reject path traversal
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        for component in components {
            if component == ".." || component == "." {
                throw HanlinHostServiceError.pathOutOfScope(path)
            }
        }

        // Reject absolute paths
        if path.hasPrefix("/") || path.hasPrefix("\\") {
            throw HanlinHostServiceError.pathOutOfScope(path)
        }

        // Reject null bytes
        if path.contains("\0") {
            throw HanlinHostServiceError.pathOutOfScope(path)
        }
    }

    // MARK: - Physical URL Resolution

    /// Get the physical URL for a virtual path in a given storage scope.
    static func physicalURL(
        for virtualPath: String,
        area: HanlinMiniAppDataArea,
        scope: HanlinHostStorageScope,
        context: HanlinHostCallContext? = nil
    ) async throws -> URL {
        try validatePath(virtualPath)

        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let baseDirectory: URL
        switch scope {
        case .app(let appID):
            let dataStore = await MainActor.run {
                HanlinMiniAppHost.shared.dataStore
            }
            let container = try await dataStore.prepareContainer(for: appID)
            baseDirectory = switch area {
            case .data: container.data
            case .documents: container.documents
            case .state: container.state
            case .cache: container.cache
            }

        case .package(let packageID):
            let areaName = area.rawValue.capitalized
            baseDirectory = appSupport
                .appending(path: "HanlinPackages", directoryHint: .isDirectory)
                .appending(path: packageID.rawValue, directoryHint: .isDirectory)
                .appending(path: areaName, directoryHint: .isDirectory)
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        case .agent:
            let areaName = area.rawValue.capitalized
            baseDirectory = appSupport
                .appending(path: "HanlinAgent", directoryHint: .isDirectory)
                .appending(path: areaName, directoryHint: .isDirectory)
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        case .shared:
            if let context {
                try await HanlinHostServicesBroker.shared.requireCapability("shared-data", context: context)
            }
            let areaName = area.rawValue.capitalized
            baseDirectory = appSupport
                .appending(path: "HanlinShared", directoryHint: .isDirectory)
                .appending(path: areaName, directoryHint: .isDirectory)
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        case .system:
            let areaName = area.rawValue.capitalized
            baseDirectory = appSupport
                .appending(path: "HanlinSystem", directoryHint: .isDirectory)
                .appending(path: areaName, directoryHint: .isDirectory)
            try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        let resolved = baseDirectory.appending(
            path: virtualPath,
            directoryHint: .notDirectory
        ).standardizedFileURL

        let basePath = baseDirectory.standardizedFileURL.path(percentEncoded: false)
        let resolvedPath = resolved.path(percentEncoded: false)
        guard resolvedPath.hasPrefix(basePath) else {
            throw HanlinHostServiceError.pathOutOfScope(virtualPath)
        }

        return resolved
    }

    /// Backward-compatible helper for appID scope.
    static func physicalURL(
        for virtualPath: String,
        area: HanlinMiniAppDataArea,
        appID: HanlinAppID
    ) async throws -> URL {
        try await physicalURL(for: virtualPath, area: area, scope: .app(appID))
    }
}
