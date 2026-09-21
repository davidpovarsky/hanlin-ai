import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

@MainActor
final class ScriptUIHostServicesAdapter {
    let context: HanlinHostCallContext
    
    init(installedPackageID: HanlinInstalledPackageID, appID: HanlinAppID, grantedCapabilities: Set<String>, sessionID: HanlinAppSessionID) {
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .scriptPackage,
            capabilities: grantedCapabilities,
            sessionID: sessionID,
            canPresentUI: true
        )
    }
    
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
    
    func writeFile(path: String, area: HanlinMiniAppDataArea, data: Data) async throws {
        try await HanlinHostServicesBroker.shared.writeFile(
            virtualPath: path,
            area: area,
            data: data,
            context: context
        )
    }
}
