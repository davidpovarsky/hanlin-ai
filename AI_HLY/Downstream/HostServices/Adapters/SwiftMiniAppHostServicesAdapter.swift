import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

@MainActor
public final class SwiftMiniAppHostServicesAdapter: NSObject, @unchecked Sendable {
    public let context: HanlinHostCallContext
    
    public init(
        appID: HanlinAppID,
        capabilities: Set<String> = [],
        sessionID: HanlinAppSessionID = try! HanlinAppSessionID(validating: UUID().uuidString.lowercased())
    ) {
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: nil,
            origin: .system,
            capabilities: capabilities,
            sessionID: sessionID,
            canPresentUI: true
        )
        super.init()
    }
    
    // Provides runtime, file, sqlite, and network services to compiled Swift mini apps
    public func executeRuntime(
        _ kind: RuntimeKind,
        source: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        return try await HanlinHostServicesBroker.shared.executeRuntime(
            kind,
            source: source,
            context: context,
            arguments: arguments,
            environment: environment,
            limits: limits
        )
    }
    
    public func readFile(path: String, area: HanlinMiniAppDataArea = .data) async throws -> Data {
        return try await HanlinHostServicesBroker.shared.readFile(
            at: path,
            area: area,
            context: context
        )
    }

    public func writeFile(path: String, data: Data, area: HanlinMiniAppDataArea = .data) async throws {
        try await HanlinHostServicesBroker.shared.writeFile(
            at: path,
            data: data,
            area: area,
            context: context
        )
    }

    public func executeSQLite(
        handle: String = "default",
        sql: String,
        arguments: [Any]? = nil
    ) async throws -> [[String: Any]] {
        return try await HanlinSQLiteHostAdapter.shared.fetchAll(
            handle: handle,
            sql: sql,
            arguments: arguments,
            context: context
        )
    }

    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)
        return try await URLSession.shared.data(from: url)
    }
}
