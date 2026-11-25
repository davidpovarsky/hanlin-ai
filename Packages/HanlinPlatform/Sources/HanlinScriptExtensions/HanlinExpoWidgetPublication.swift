import Foundation
import HanlinPlatformContracts

/// The committed prepared-program state, not an observation of WidgetKit rendering.
public struct HanlinExpoWidgetStateReceipt: Codable, Equatable, Sendable {
    public let installedPackageID: String
    public let packageID: String
    public let generation: UInt64
    public let entrypointID: String
    public let variantID: String
    public let entityID: String
    public let artifactSHA256: String
    public let revision: UInt64
    public let supportedFamilies: [String]
}

extension HanlinScriptExtensionStore {
    /// Replace the current props of one installed Expo widget instance. All its
    /// families consume this same state through HanlinWidgetPreparation.prepare.
    /// This uses the same transaction as source callbacks and retains their nonces.
    public func publishExpoWidgetProps(
        identity: HanlinScriptExtensionIdentity,
        props: [String: HanlinValue]
    ) throws -> HanlinExpoWidgetStateReceipt {
        // Validate actual JSON before entering the transaction; no host size budget.
        _ = try HanlinValue.object(HanlinObject(uniqueMembers: Array(props))).canonicalJSONData(limits: .unbounded)
        var receipt: HanlinExpoWidgetStateReceipt?
        try update { current in
            guard let current,
                  !current.inactiveWidgetInstallations.contains(identity.installedPackageID.rawValue),
                  let instance = current.widgetInstances.first(where: { $0.identity == identity && $0.engine == .expo }) else {
                throw HanlinWidgetActionError.inactiveInstance
            }
            let widgets = current.widgets.filter { $0.identity == identity && $0.engine == .expo }
            guard let first = widgets.first, widgets.allSatisfy({ $0.validUntil > .now }) else {
                throw HanlinWidgetActionError.inactiveInstance
            }
            let (_, digest) = try loadProgram(for: first)
            // Every advertised family must resolve the same authenticated program.
            for widget in widgets.dropFirst() {
                guard try loadProgram(for: widget).1 == digest else { throw HanlinWidgetActionError.staleArtifact }
            }
            let old = current.widgetStates.first { $0.identity == identity && $0.engine == .expo }
            guard old == nil || old?.artifactSHA256 == digest else { throw HanlinWidgetActionError.staleArtifact }
            var state = old ?? .init(identity: identity, engine: .expo, artifactSHA256: digest)
            guard state.revision < UInt64.max else { throw HanlinWidgetActionError.invalidState }
            state.values = props
            state.revision += 1
            var states = current.widgetStates.filter { !($0.identity == identity && $0.engine == .expo) }
            states.append(state)
            receipt = .init(installedPackageID: identity.installedPackageID.rawValue,
                packageID: identity.packageID.rawValue, generation: identity.generation,
                entrypointID: identity.entrypointID, variantID: identity.variantID,
                entityID: instance.entityID, artifactSHA256: digest, revision: state.revision,
                supportedFamilies: Array(Set(widgets.map(\.family))).sorted())
            return current.replacing(states: states)
        }
        guard let receipt else { throw HanlinWidgetActionError.inactiveInstance }
        return receipt
    }
}
