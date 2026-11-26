import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

/// A render is reusable only for the exact installed program, instance settings
/// and family that produced it. Payload bytes use the existing verified artifact
/// store; URLs and action authority are reconstructed from the current snapshot.
public struct HanlinWidgetLastSuccessfulRender: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let engine: HanlinWidgetEngine
    public let family: String
    public let programSHA256: String
    public let settings: [String: HanlinValue]
    public let renderRef: String
    public let renderSHA256: String
    public let renderedAt: Date

    public init(identity: HanlinScriptExtensionIdentity, engine: HanlinWidgetEngine,
                family: String, programSHA256: String, settings: [String: HanlinValue],
                renderRef: String, renderSHA256: String, renderedAt: Date) {
        self.identity = identity
        self.engine = engine
        self.family = family
        self.programSHA256 = programSHA256
        self.settings = settings
        self.renderRef = renderRef
        self.renderSHA256 = renderSHA256
        self.renderedAt = renderedAt
    }

    func matches(widget: HanlinScriptWidgetSnapshot, instance: HanlinWidgetInstance,
                 programSHA256: String) -> Bool {
        identity == widget.identity && identity == instance.identity
            && engine == widget.engine && engine == instance.engine
            && family == widget.family && self.programSHA256 == programSHA256
            && settings == instance.settings
    }
}

enum HanlinCachedWidgetNode: Codable, Hashable, Sendable {
    case expo(HanlinValue)
    case scriptwidget(HanlinScriptWidgetPreparedNode)

    var engine: HanlinWidgetEngine {
        switch self {
        case .expo: .expo
        case .scriptwidget: .scriptwidget
        }
    }
}

extension HanlinScriptExtensionStore {
    func storeSuccessfulWidgetNode(_ node: HanlinCachedWidgetNode,
                                   widget: HanlinScriptWidgetSnapshot,
                                   instance: HanlinWidgetInstance,
                                   programSHA256: String) throws -> HanlinWidgetLastSuccessfulRender {
        guard node.engine == widget.engine, widget.identity == instance.identity,
              widget.engine == instance.engine else { throw HanlinWidgetActionError.invalidIdentity }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let artifact = try storeArtifact(data: encoder.encode(node),
            installedPackageID: widget.identity.installedPackageID, generation: widget.identity.generation)
        return .init(identity: widget.identity, engine: widget.engine, family: widget.family,
            programSHA256: programSHA256, settings: instance.settings, renderRef: artifact.ref,
            renderSHA256: artifact.sha256, renderedAt: .now)
    }

    /// Caller must first validate the live program, active instance and resources.
    /// Cache corruption is never accepted as a reason to relax artifact checks.
    func lastSuccessfulWidgetNode(in snapshot: HanlinScriptExtensionSnapshot,
                                  widget: HanlinScriptWidgetSnapshot,
                                  instance: HanlinWidgetInstance,
                                  programSHA256: String) throws -> HanlinCachedWidgetNode? {
        guard !snapshot.inactiveWidgetInstallations.contains(widget.identity.installedPackageID.rawValue),
              widget.validUntil > .now,
              snapshot.widgetInstances.contains(instance),
              snapshot.widgets.contains(widget),
              let record = snapshot.widgetLastSuccessfulRenders.first(where: {
                  $0.matches(widget: widget, instance: instance, programSHA256: programSHA256)
              }) else { return nil }
        let data = try loadVerifiedArtifact(ref: record.renderRef, sha256: record.renderSHA256,
            installedPackageID: widget.identity.installedPackageID, generation: widget.identity.generation)
        let node = try JSONDecoder().decode(HanlinCachedWidgetNode.self, from: data)
        guard node.engine == widget.engine else { throw HanlinWidgetProgramError.invalidProgram }
        return node
    }
}

extension HanlinScriptExtensionSnapshot {
    func retainingSuccessfulWidgetRender(_ record: HanlinWidgetLastSuccessfulRender,
                                        states: [HanlinWidgetInstanceState]? = nil) -> Self {
        let retained = widgetLastSuccessfulRenders.filter {
            !($0.identity == record.identity && $0.engine == record.engine && $0.family == record.family)
        } + [record]
        return replacing(states: states, lastSuccessfulRenders: retained)
    }
}
