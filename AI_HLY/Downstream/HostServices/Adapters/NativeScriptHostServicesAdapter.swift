import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Session-bound bridge replacing global statics in `HanlinNativeServicesHostProvider`.
@MainActor
final class NativeScriptHostServicesAdapter {
    let context: HanlinHostCallContext

    init(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID,
        grantedCapabilities: Set<String>
    ) {
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .nativeModule,
            capabilities: grantedCapabilities,
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
        try await HanlinRuntimeBroker.shared.execute(
            kind: kind,
            source: source,
            context: context,
            arguments: arguments,
            environment: environment,
            limits: limits
        )
    }

    func fetchURL(_ urlString: String) async throws -> (Data, Int) {
        try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw HanlinHostServiceError.invalidRequest("Only HTTPS URLs are supported")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        return (data, statusCode)
    }

    func hasCapability(_ capability: String) -> Bool {
        let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capability)
        return context.effectiveCapabilities.contains(canonical)
            || context.effectiveCapabilities.contains("all")
    }
}
