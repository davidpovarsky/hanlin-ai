import Foundation
import HanlinPlatformContracts

public enum HanlinMiniAppDataArea: String, Codable, CaseIterable, Hashable, Sendable {
    case data = "Data"
    case documents = "Documents"
    case state = "State"
    case cache = "Cache"
}

public struct HanlinMiniAppDataLimits: Hashable, Sendable {
    public let maximumFileBytes: Int?
    public let maximumPersistentBytes: Int?
    public let maximumCacheBytes: Int?

    public init(
        maximumFileBytes: Int? = nil,
        maximumPersistentBytes: Int? = nil,
        maximumCacheBytes: Int? = nil
    ) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumPersistentBytes = maximumPersistentBytes
        self.maximumCacheBytes = maximumCacheBytes
    }
}

public enum HanlinMiniAppDataError: Error, Equatable, Sendable {
    case invalidPath(String)
    case symbolicLink(String)
    case quotaExceeded(HanlinMiniAppDataArea)
    case fileTooLarge
}

/// Trusted-host directory projection. It must never be placed in an untrusted script payload.
public struct HanlinMiniAppContainerDirectories: Sendable {
    public let root: URL
    public let data: URL
    public let documents: URL
    public let state: URL
    public let cache: URL

    public init(root: URL, data: URL, documents: URL, state: URL, cache: URL) {
        self.root = root
        self.data = data
        self.documents = documents
        self.state = state
        self.cache = cache
    }
}

/// Canonical durable storage for every Mini App engine.
///
/// Identity is the canonical app ID, never an installed generation or artifact path.
public actor HanlinMiniAppDataStore {
    private let root: URL
    private let limits: HanlinMiniAppDataLimits
    private let fileManager: FileManager

    public init(
        root: URL,
        limits: HanlinMiniAppDataLimits = .init(),
        fileManager: FileManager = .default
    ) throws {
        self.root = root.standardizedFileURL
        self.limits = limits
        self.fileManager = fileManager
        try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    public static func applicationSupportRoot(fileManager: FileManager = .default) throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return support.appending(path: "Hanlin/MiniApps", directoryHint: .isDirectory)
    }

    public func prepareContainer(for appID: HanlinAppID) throws -> HanlinMiniAppContainerDirectories {
        let appRoot = root.appending(path: appID.rawValue, directoryHint: .isDirectory)
        try rejectSymbolicLinkIfPresent(appRoot, reportedPath: appID.rawValue)
        let directories = HanlinMiniAppContainerDirectories(
            root: appRoot,
            data: appRoot.appending(path: HanlinMiniAppDataArea.data.rawValue, directoryHint: .isDirectory),
            documents: appRoot.appending(path: HanlinMiniAppDataArea.documents.rawValue, directoryHint: .isDirectory),
            state: appRoot.appending(path: HanlinMiniAppDataArea.state.rawValue, directoryHint: .isDirectory),
            cache: appRoot.appending(path: HanlinMiniAppDataArea.cache.rawValue, directoryHint: .isDirectory)
        )
        for directory in [directories.data, directories.documents, directories.state, directories.cache] {
            try rejectSymbolicLinkIfPresent(directory, reportedPath: directory.lastPathComponent)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directories
    }

    public func read(
        appID: HanlinAppID,
        area: HanlinMiniAppDataArea,
        path: String
    ) throws -> Data? {
        let target = try containedURL(appID: appID, area: area, path: path)
        guard fileManager.fileExists(atPath: target.path(percentEncoded: false)) else { return nil }
        let values = try target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw HanlinMiniAppDataError.symbolicLink(path) }
        guard values.isRegularFile == true else { throw HanlinMiniAppDataError.invalidPath(path) }
        if let maxBytes = limits.maximumFileBytes, (values.fileSize ?? 0) > maxBytes {
            throw HanlinMiniAppDataError.fileTooLarge
        }
        return try Data(contentsOf: target, options: .mappedIfSafe)
    }

    public func write(
        _ data: Data,
        appID: HanlinAppID,
        area: HanlinMiniAppDataArea,
        path: String
    ) throws {
        if let maxFile = limits.maximumFileBytes, data.count > maxFile {
            throw HanlinMiniAppDataError.fileTooLarge
        }
        let target = try containedURL(appID: appID, area: area, path: path)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let areaRoot = try areaRoot(appID: appID, area: area)

        if area == .cache {
            if let maxCache = limits.maximumCacheBytes {
                let projected = try recursiveByteCount(at: areaRoot) - existing + data.count
                guard projected <= maxCache else { throw HanlinMiniAppDataError.quotaExceeded(area) }
            }
        } else {
            if let maxPersistent = limits.maximumPersistentBytes {
                let directories = try prepareContainer(for: appID)
                let projected = try [directories.data, directories.documents, directories.state]
                    .reduce(data.count - existing) { total, directory in
                        total + (try recursiveByteCount(at: directory))
                    }
                guard projected <= maxPersistent else { throw HanlinMiniAppDataError.quotaExceeded(area) }
            }
        }
        try data.write(to: target, options: [.atomic])
    }

    public func remove(appID: HanlinAppID, area: HanlinMiniAppDataArea, path: String) throws {
        let target = try containedURL(appID: appID, area: area, path: path)
        guard fileManager.fileExists(atPath: target.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: target)
    }

    public func list(appID: HanlinAppID, area: HanlinMiniAppDataArea) throws -> [String] {
        let areaRoot = try areaRoot(appID: appID, area: area)
        guard let enumerator = fileManager.enumerator(
            at: areaRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [String] = []
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true {
                result.append(String(item.path(percentEncoded: false).dropFirst(areaRoot.path(percentEncoded: false).count + 1)))
            }
        }
        return result.sorted()
    }

    private func areaRoot(appID: HanlinAppID, area: HanlinMiniAppDataArea) throws -> URL {
        let directories = try prepareContainer(for: appID)
        return switch area {
        case .data: directories.data
        case .documents: directories.documents
        case .state: directories.state
        case .cache: directories.cache
        }
    }

    private func containedURL(
        appID: HanlinAppID,
        area: HanlinMiniAppDataArea,
        path: String
    ) throws -> URL {
        guard !path.isEmpty, path.utf8.count <= 8_192, !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("\0") else {
            throw HanlinMiniAppDataError.invalidPath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw HanlinMiniAppDataError.invalidPath(path)
        }
        let base = try areaRoot(appID: appID, area: area).standardizedFileURL
        var checked = base
        for component in components {
            checked.append(path: String(component), directoryHint: .inferFromPath)
            try rejectSymbolicLinkIfPresent(checked, reportedPath: path)
        }
        checked = checked.standardizedFileURL
        let basePath = base.path(percentEncoded: false)
        guard checked.path(percentEncoded: false).hasPrefix(basePath + "/") else {
            throw HanlinMiniAppDataError.invalidPath(path)
        }
        return checked
    }

    private func rejectSymbolicLinkIfPresent(_ url: URL, reportedPath: String) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw HanlinMiniAppDataError.symbolicLink(reportedPath)
        }
    }

    private func recursiveByteCount(at directory: URL) throws -> Int {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
        }
        return total
    }
}

/// A capability object bound to exactly one canonical Mini App identity.
/// Mini App package code never receives the root store or an app-ID parameter.
public struct HanlinMiniAppStorageContext: Sendable {
    public let appID: HanlinAppID
    private let store: HanlinMiniAppDataStore

    public init(appID: HanlinAppID, store: HanlinMiniAppDataStore) {
        self.appID = appID
        self.store = store
    }

    public func read(area: HanlinMiniAppDataArea, path: String) async throws -> Data? {
        try await store.read(appID: appID, area: area, path: path)
    }

    public func write(_ data: Data, area: HanlinMiniAppDataArea, path: String) async throws {
        try await store.write(data, appID: appID, area: area, path: path)
    }

    public func remove(area: HanlinMiniAppDataArea, path: String) async throws {
        try await store.remove(appID: appID, area: area, path: path)
    }

    public func list(area: HanlinMiniAppDataArea) async throws -> [String] {
        try await store.list(appID: appID, area: area)
    }
}
