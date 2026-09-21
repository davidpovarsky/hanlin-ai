import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Per-app SQLite service management through the unified host services layer.
/// Creates and caches `HanlinSQLiteService` instances scoped to each app's
/// `State` directory within the canonical data store.
actor HanlinSQLiteHostAdapter {
    static let shared = HanlinSQLiteHostAdapter()

    /// Cached service instances keyed by app ID raw value.
    private var services: [String: HanlinSQLiteService] = [:]

    private init() {}

    // MARK: - Service Resolution

    /// Get or create a SQLite service for the given context.
    func service(for context: HanlinHostCallContext) async throws -> HanlinSQLiteService {
        try await HanlinHostServicesBroker.shared.requireCapability("sqlite", context: context)

        guard let appID = context.appID else {
            throw HanlinHostServiceError.invalidCallerContext(
                "SQLite operations require an app context"
            )
        }

        let key = appID.rawValue
        if let existing = services[key] {
            return existing
        }

        // Access data store from MainActor-isolated HanlinMiniAppHost
        let container = await MainActor.run {
            HanlinMiniAppHost.shared.dataStore
        }
        let directories = try await container.prepareContainer(for: appID)
        let service = HanlinSQLiteService(rootURL: directories.state)
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
