import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public struct HanlinWidgetActionContext: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let engine: HanlinWidgetEngine
    public let artifactSHA256: String
    public let family: String
    public let environment: [String: HanlinValue]
    public let actions: [HanlinWidgetActionDeclaration]
    public let resources: [String: URL]

    public init(identity: HanlinScriptExtensionIdentity, engine: HanlinWidgetEngine,
                artifactSHA256: String, family: String, environment: [String: HanlinValue] = [:],
                actions: [HanlinWidgetActionDeclaration] = [], resources: [String: URL] = [:]) {
        self.identity = identity
        self.engine = engine
        self.artifactSHA256 = artifactSHA256
        self.family = family
        self.environment = environment
        self.actions = actions
        self.resources = resources
    }
}

public enum HanlinPreparedWidget: Sendable {
    case legacy(HanlinScriptWidgetSnapshot)
    case expo(node: HanlinValue, context: HanlinWidgetActionContext)
    case scriptwidget(node: HanlinScriptWidgetPreparedNode, context: HanlinWidgetActionContext)
    case failure(String)
}

public struct HanlinScriptWidgetPreparedNode: Codable, Hashable, Sendable {
    public let tag: String
    public let props: [String: HanlinValue]
    public let children: [Child]
    public indirect enum Child: Codable, Hashable, Sendable {
        case element(HanlinScriptWidgetPreparedNode)
        case value(HanlinValue)
    }
    public init(tag: String, props: [String: HanlinValue], children: [Child]) {
        self.tag = tag
        self.props = props
        self.children = children
    }
}

enum HanlinWidgetJSON {
    static func value(_ object: Any) throws -> HanlinValue {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
        return try HanlinValue(jsonValue: HanlinJSONValue.decodeCanonicalJSON(data, limits: .init(maximumPayloadBytes: 256 * 1_024, maximumNodes: 1_000)))
    }

    static func dictionary(_ object: [String: Any]) throws -> [String: HanlinValue] {
        try object.mapValues(value)
    }
}

extension HanlinScriptExtensionStore {
    public func loadProgram(for widget: HanlinScriptWidgetSnapshot) throws -> (HanlinWidgetProgram, String) {
        let ref: String?, digest: String?
        switch widget.payload {
        case let .expo(descriptor): (ref, digest) = (descriptor.layoutRef, descriptor.layoutSHA256)
        case let .scriptwidget(descriptor): (ref, digest) = (descriptor.scriptRef, descriptor.scriptSHA256)
        default: throw HanlinWidgetProgramError.invalidProgram
        }
        guard let ref, let digest else { throw HanlinScriptExtensionStoreError.artifactMissing }
        let bytes = try loadVerifiedArtifact(ref: ref, sha256: digest,
            installedPackageID: widget.identity.installedPackageID, generation: widget.identity.generation)
        let program = try JSONDecoder().decode(HanlinWidgetProgram.self, from: bytes)
        try program.validate(engine: widget.engine)
        guard program.families.contains(widget.family) else { throw HanlinWidgetProgramError.invalidProgram }
        return (program, digest)
    }
}

public enum HanlinWidgetPreparation {
    public static func prepare(store: HanlinScriptExtensionStore, entityID: String, family: String) -> HanlinPreparedWidget {
        do {
            guard let snapshot = try store.load(),
                  let widget = snapshot.widgets.first(where: { widget in
                      HanlinWidgetInstance(identity: widget.identity, engine: widget.engine, displayName: widget.displayName).entityID == entityID
                          && widget.family == family
                  }) else { return .failure("The selected widget is unavailable, disabled or belongs to an older generation.") }
            if case let .malformed(reason) = widget.payload { return .failure(reason) }
            guard !snapshot.inactiveWidgetInstallations.contains(widget.identity.installedPackageID.rawValue) else { return .failure("Widget package is being updated or is disabled.") }
            guard widget.validUntil > .now else { return .failure("The widget snapshot has expired. Open Hanlin to republish it.") }
            if widget.engine == .legacy { return .legacy(widget) }
            guard snapshot.widgetInstances.contains(where: { $0.identity == widget.identity && $0.engine == widget.engine }) else {
                return .failure("This widget instance is no longer active.")
            }
            let (program, digest) = try store.loadProgram(for: widget)
            let state = snapshot.widgetStates.first { $0.identity == widget.identity && $0.engine == widget.engine && $0.artifactSHA256 == digest }
            var environment: [String: HanlinValue] = ["widgetFamily": .string(family), "family": .string(family),
                "timestamp": .number(Date.now.timeIntervalSince1970 * 1_000)]
            if case let .scriptwidget(descriptor) = widget.payload {
                environment.merge(descriptor.environment ?? [:]) { current, _ in current }
            }
            let resources = try store.materializeResources(program.resources, identity: widget.identity)
            let context = HanlinWidgetActionContext(identity: widget.identity, engine: widget.engine, artifactSHA256: digest,
                family: family, environment: environment, actions: program.actions, resources: resources)
            if widget.engine == .expo {
                let props = state?.values ?? {
                    if case let .expo(descriptor) = widget.payload { return descriptor.props ?? [:] }
                    return [:]
                }()
                let node = try HanlinExpoWidgetsRuntime.shared.render(layout: program.javaScript,
                    props: props.mapValues { $0.toAny() }, environment: environment.mapValues { $0.toAny() }).get()
                return .expo(node: try HanlinWidgetJSON.value(node), context: context)
            }
            let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: state?.values ?? [:], environment: environment)
            return .scriptwidget(node: result.node, context: context)
        } catch { return .failure("Widget preparation failed: \(error)") }
    }
}
