import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts

extension SplitBridgeRequest {
    /// Preserve canonical identity and payload exactly. The existing broker and
    /// HostServices must authorize this request; the adapter grants nothing.
    public func canonicalRequest() -> HanlinMiniAppRequest {
        HanlinMiniAppRequest(id: id, caller: caller, target: target, action: action,
                            capability: capability, payload: payload)
    }

    public func canonicalReturn(_ response: HanlinMiniAppResponse) throws -> SplitBridgeReturn {
        guard response.requestID == id else { throw SplitBridgeFailure.correlationMismatch }
        return SplitBridgeReturn(request: self, outcome: .result(response.value))
    }

    /// Validate descriptor/package identity using canonical launch planning.
    /// The caller must obtain package/generation from the live installed registry,
    /// not from URL fields, and separately reevaluate user/system authorization.
    public func launchPlan(descriptor: HanlinAppDescriptor,
                           installedPackageID: HanlinInstalledPackageID,
                           currentGeneration: UInt64) throws -> HanlinMiniAppLaunchPlan {
        guard target == descriptor.id, installedPackage == installedPackageID else {
            throw SplitBridgeFailure.correlationMismatch
        }
        guard generation == currentGeneration else { throw SplitBridgeFailure.staleGeneration }
        guard descriptor.actions.contains(where: {
            $0.id == action && $0.capabilities.contains(capability)
        }), descriptor.capabilities.contains(where: { $0.id == capability })
        else { throw SplitBridgeFailure.unsupportedRoute }
        return try HanlinMiniAppLaunchPlan(descriptor: descriptor, entryPointKind: entryPoint)
    }
}
