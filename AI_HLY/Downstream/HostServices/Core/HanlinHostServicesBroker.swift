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

    func requireCapability(_ capabilityID: String, context: HanlinHostCallContext) async throws {
        let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capabilityID)
        let result = await capabilityAuthority.authorize(capability: canonical, context: context)
        guard result == .allowed else {
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

    func readFile(
        virtualPath: String,
        area: HanlinMiniAppDataArea,
        context: HanlinHostCallContext
    ) async throws -> Data? {
        try await requireCapability("files", context: context)
        let fileURL = try await HanlinFileService.physicalURL(
            for: virtualPath,
            area: area,
            scope: context.storageScope,
            context: context
        )
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    func writeFile(
        virtualPath: String,
        area: HanlinMiniAppDataArea,
        data: Data,
        context: HanlinHostCallContext
    ) async throws {
        try await requireCapability("files", context: context)
        let fileURL = try await HanlinFileService.physicalURL(
            for: virtualPath,
            area: area,
            scope: context.storageScope,
            context: context
        )
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func deleteFile(
        virtualPath: String,
        area: HanlinMiniAppDataArea,
        context: HanlinHostCallContext
    ) async throws {
        try await requireCapability("files", context: context)
        let fileURL = try await HanlinFileService.physicalURL(
            for: virtualPath,
            area: area,
            scope: context.storageScope,
            context: context
        )
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    func listFiles(
        area: HanlinMiniAppDataArea,
        context: HanlinHostCallContext
    ) async throws -> [String] {
        try await requireCapability("files", context: context)
        if case .app(let appID) = context.storageScope {
            return try await resolveDataStore().list(appID: appID, area: area)
        }
        let areaDir = try await HanlinFileService.physicalURL(
            for: "temp-probe",
            area: area,
            scope: context.storageScope,
            context: context
        ).deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.fileExists(atPath: areaDir.path(percentEncoded: false)) else {
            return []
        }
        return try fm.contentsOfDirectory(atPath: areaDir.path(percentEncoded: false))
    }
}
