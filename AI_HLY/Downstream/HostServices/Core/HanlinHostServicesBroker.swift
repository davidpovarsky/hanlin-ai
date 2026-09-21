import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Top-level host services facade routing all caller requests through
/// unified capability checks, workspace derivation, and service dispatch.
actor HanlinHostServicesBroker {
    static let shared = HanlinHostServicesBroker()

    nonisolated let capabilityAuthority = HanlinHostCapabilityAuthority.shared
    nonisolated let runtimeBroker = HanlinRuntimeBroker.shared
    nonisolated let availability = RuntimeAvailabilityStore.shared

    private init() {}

    // MARK: - Capability Checks

    func requireCapability(_ capabilityID: String, context: HanlinHostCallContext) throws {
        let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capabilityID)
        guard context.effectiveCapabilities.contains(canonical)
            || context.effectiveCapabilities.contains("all") else {
            throw HanlinHostServiceError.capabilityNotGranted(canonical)
        }
    }

    // MARK: - Runtime Operations

    func executeRuntime(
        _ kind: RuntimeKind,
        source: String,
        context: HanlinHostCallContext,
        arguments: [String] = [],
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        try await runtimeBroker.execute(
            kind: kind,
            source: source,
            context: context,
            arguments: arguments,
            environment: environment,
            limits: limits
        )
    }

    // MARK: - File Operations

    /// Resolve the canonical data store for file operations.
    /// `HanlinMiniAppHost.shared` is `@MainActor`, so we access it accordingly.
    @MainActor
    private static var _dataStore: HanlinMiniAppDataStore {
        HanlinMiniAppHost.shared.dataStore
    }

    private func resolveDataStore() async -> HanlinMiniAppDataStore {
        await Self._dataStore
    }

    private func requireAppID(_ context: HanlinHostCallContext) throws -> HanlinAppID {
        guard let appID = context.appID else {
            throw HanlinHostServiceError.invalidCallerContext(
                "File operations require an app context"
            )
        }
        return appID
    }

    func readFile(
        virtualPath: String,
        area: HanlinMiniAppDataArea,
        context: HanlinHostCallContext
    ) async throws -> Data? {
        try requireCapability("files", context: context)
        let appID = try requireAppID(context)
        return try await resolveDataStore().read(appID: appID, area: area, path: virtualPath)
    }

    func writeFile(
        virtualPath: String,
        area: HanlinMiniAppDataArea,
        data: Data,
        context: HanlinHostCallContext
    ) async throws {
        try requireCapability("files", context: context)
        let appID = try requireAppID(context)
        try await resolveDataStore().write(data, appID: appID, area: area, path: virtualPath)
    }

    func deleteFile(
        virtualPath: String,
        area: HanlinMiniAppDataArea,
        context: HanlinHostCallContext
    ) async throws {
        try requireCapability("files", context: context)
        let appID = try requireAppID(context)
        try await resolveDataStore().remove(appID: appID, area: area, path: virtualPath)
    }

    func listFiles(
        area: HanlinMiniAppDataArea,
        context: HanlinHostCallContext
    ) async throws -> [String] {
        try requireCapability("files", context: context)
        let appID = try requireAppID(context)
        return try await resolveDataStore().list(appID: appID, area: area)
    }
}
