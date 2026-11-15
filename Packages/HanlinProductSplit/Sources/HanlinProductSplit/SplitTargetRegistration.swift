import HanlinMiniAppCore
import HanlinPlatformContracts

/// Export of the MiniApps host's canonical catalog, not a second installed registry.
/// Sender discovery is advisory; the receiving host rechecks its live package state.
public struct SplitTargetRegistration: Codable, Hashable, Sendable {
    public let descriptor: HanlinAppDescriptor
    public let installedPackage: HanlinInstalledPackageID
    public let generation: UInt64

    public init(descriptor: HanlinAppDescriptor, installedPackage: HanlinInstalledPackageID, generation: UInt64) throws {
        self.descriptor = descriptor
        self.installedPackage = installedPackage
        self.generation = generation
        try validate()
    }

    public func validate() throws {
        try descriptor.validate()
        _ = try HanlinMiniAppLaunchPlan(descriptor: descriptor)
    }
}
