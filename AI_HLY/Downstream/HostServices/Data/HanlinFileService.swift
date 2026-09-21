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

    /// Get the physical URL for a virtual path in a given app context.
    /// Resolves through the canonical `HanlinMiniAppDataStore`.
    static func physicalURL(
        for virtualPath: String,
        area: HanlinMiniAppDataArea,
        appID: HanlinAppID
    ) async throws -> URL {
        try validatePath(virtualPath)

        let dataStore = await MainActor.run {
            HanlinMiniAppHost.shared.dataStore
        }
        let container = try await dataStore.prepareContainer(for: appID)

        let areaURL: URL = switch area {
        case .data: container.data
        case .documents: container.documents
        case .state: container.state
        case .cache: container.cache
        }

        let resolved = areaURL.appending(
            path: virtualPath,
            directoryHint: .notDirectory
        ).standardizedFileURL

        // Verify the resolved path is still under the area root
        let areaPath = areaURL.standardizedFileURL.path(percentEncoded: false)
        let resolvedPath = resolved.path(percentEncoded: false)
        guard resolvedPath.hasPrefix(areaPath) else {
            throw HanlinHostServiceError.pathOutOfScope(virtualPath)
        }

        return resolved
    }
}
