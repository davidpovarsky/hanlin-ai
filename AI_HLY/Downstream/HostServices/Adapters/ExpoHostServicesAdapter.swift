import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Host services adapter for Expo/React Native Mini Apps.
/// Provides the first capability-gated host service bridge for the Expo engine.
@MainActor
final class ExpoHostServicesAdapter {
    let context: HanlinHostCallContext

    init(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID,
        grantedCapabilities: Set<String>
    ) {
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .scriptPackage,
            capabilities: grantedCapabilities,
            canPresentUI: true
        )
    }

    func hasCapability(_ capability: String) -> Bool {
        let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capability)
        return context.effectiveCapabilities.contains(canonical)
            || context.effectiveCapabilities.contains("all")
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
}
