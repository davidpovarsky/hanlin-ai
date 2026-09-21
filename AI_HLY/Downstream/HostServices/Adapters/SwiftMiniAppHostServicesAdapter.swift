import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

@MainActor
final class SwiftMiniAppHostServicesAdapter {
    let context: HanlinHostCallContext
    
    init(appID: HanlinAppID, capabilities: Set<String>, sessionID: HanlinAppSessionID) {
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: nil,
            origin: .system,
            capabilities: capabilities,
            sessionID: sessionID,
            canPresentUI: true
        )
    }
    
    // Provides runtime, file, and system services to compiled Swift mini apps
    func executeRuntime(
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
    
    func readFile(path: String, area: HanlinMiniAppDataArea) async throws -> Data? {
        return try await HanlinHostServicesBroker.shared.readFile(
            virtualPath: path,
            area: area,
            context: context
        )
    }
}
