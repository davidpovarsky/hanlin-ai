import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Per-app SQLite service management through the unified host services layer.
/// Creates and caches `HanlinSQLiteService` instances scoped to each app's
/// `State` directory within the canonical data store.
actor HanlinSQLiteHostAdapter {
    static let shared = HanlinSQLiteHostAdapter()

    /// Cached service instances keyed by storage scope key.
    private var services: [String: HanlinSQLiteService] = [:]

    private init() {}

    // MARK: - Service Resolution

    private func scopeKey(for scope: HanlinHostStorageScope) -> String {
        switch scope {
        case .app(let appID): return "app:\(appID.rawValue)"
        case .package(let packageID): return "package:\(packageID.rawValue)"
        case .agent: return "agent"
        case .shared: return "shared"
        case .system: return "system"
        }
    }

    private func resolveRootURL(for scope: HanlinHostStorageScope, context: HanlinHostCallContext) async throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        switch scope {
        case .app(let appID):
            let container = await MainActor.run {
                HanlinMiniAppHost.shared.dataStore
            }
            let directories = try await container.prepareContainer(for: appID)
            return directories.state

        case .package(let packageID):
            let pkgState = appSupport
                .appending(path: "HanlinPackages", directoryHint: .isDirectory)
                .appending(path: packageID.rawValue, directoryHint: .isDirectory)
                .appending(path: "State", directoryHint: .isDirectory)
            try fm.createDirectory(at: pkgState, withIntermediateDirectories: true)
            return pkgState

        case .agent:
            let agentState = appSupport
                .appending(path: "HanlinAgent", directoryHint: .isDirectory)
                .appending(path: "State", directoryHint: .isDirectory)
            try fm.createDirectory(at: agentState, withIntermediateDirectories: true)
            return agentState

        case .shared:
            try await HanlinHostServicesBroker.shared.requireCapability("shared-data", context: context)
            let sharedState = appSupport
                .appending(path: "HanlinShared", directoryHint: .isDirectory)
                .appending(path: "State", directoryHint: .isDirectory)
            try fm.createDirectory(at: sharedState, withIntermediateDirectories: true)
            return sharedState

        case .system:
            let systemState = appSupport
                .appending(path: "HanlinSystem", directoryHint: .isDirectory)
                .appending(path: "State", directoryHint: .isDirectory)
            try fm.createDirectory(at: systemState, withIntermediateDirectories: true)
            return systemState
        }
    }

    /// Get or create a SQLite service for the given context.
    func service(for context: HanlinHostCallContext) async throws -> HanlinSQLiteService {
        try await HanlinHostServicesBroker.shared.requireCapability("sqlite", context: context)

        let key = scopeKey(for: context.storageScope)
        if let existing = services[key] {
            return existing
        }

        let rootURL = try await resolveRootURL(for: context.storageScope, context: context)
        let service = HanlinSQLiteService(rootURL: rootURL)
        services[key] = service
        return service
    }

    // MARK: - Capability-Checked Operations

    func open(
        handle: String,
        name: String,
        context: HanlinHostCallContext,
        readonly: Bool = false,
        foreignKeys: Bool = false,
        walMode: Bool = true,
        busyTimeoutMs: Int32 = 5_000
    ) async throws -> String {
        let svc = try await service(for: context)
        return try svc.open(
            handle: handle,
            name: name,
            readonly: readonly,
            foreignKeys: foreignKeys,
            walMode: walMode,
            busyTimeoutMs: busyTimeoutMs
        )
    }

    func close(handle: String, context: HanlinHostCallContext) async throws {
        let svc = try await service(for: context)
        svc.close(handle: handle)
    }

    func execute(
        handle: String,
        sql: String,
        arguments: [Any]? = nil,
        context: HanlinHostCallContext
    ) async throws {
        let svc = try await service(for: context)
        try svc.execute(handle: handle, sql: sql, arguments: arguments)
    }

    func fetchAll(
        handle: String,
        sql: String,
        arguments: [Any]? = nil,
        context: HanlinHostCallContext
    ) async throws -> [[String: Any]] {
        let svc = try await service(for: context)
        return try svc.fetchAll(handle: handle, sql: sql, arguments: arguments)
    }

    /// Sendable-safe variant: serialises the result to a JSON string inside the actor
    /// before returning, avoiding [[String: Any]] crossing the actor boundary.
    func fetchAllJSON(
        handle: String,
        sql: String,
        arguments: [Any]? = nil,
        context: HanlinHostCallContext
    ) async throws -> String {
        let svc = try await service(for: context)
        let rows = try svc.fetchAll(handle: handle, sql: sql, arguments: arguments)
        guard JSONSerialization.isValidJSONObject(rows) else { return "[]" }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Session Cleanup

    /// Close all databases and remove the cached service for an app.
    func endSession(appID: HanlinAppID) {
        let key = appID.rawValue
        if let service = services.removeValue(forKey: key) {
            service.closeAll()
        }
    }

    /// Close all databases across all apps.
    func endAllSessions() {
        for service in services.values {
            service.closeAll()
        }
        services.removeAll()
    }
}
