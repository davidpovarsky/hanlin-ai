import CryptoKit
import Foundation
import OSLog
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptUI

public struct HanlinWidgetActionContext: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let engine: HanlinWidgetEngine
    public let artifactSHA256: String
    public let family: String
    public let environment: [String: HanlinValue]
    public let actions: [HanlinWidgetActionDeclaration]
    public let resources: [String: URL]
    public let presentation: HanlinNativePresentationRequest?

    public init(identity: HanlinScriptExtensionIdentity, engine: HanlinWidgetEngine,
                artifactSHA256: String, family: String, environment: [String: HanlinValue] = [:],
                actions: [HanlinWidgetActionDeclaration] = [], resources: [String: URL] = [:],
                presentation: HanlinNativePresentationRequest? = nil) {
        self.identity = identity
        self.engine = engine
        self.artifactSHA256 = artifactSHA256
        self.family = family
        self.environment = environment
        self.actions = actions
        self.resources = resources
        self.presentation = presentation
    }
}

public enum HanlinPreparedWidget: Sendable {
    case legacy(HanlinScriptWidgetSnapshot)
    case expo(node: HanlinValue, context: HanlinWidgetActionContext)
    case scriptwidget(node: HanlinScriptWidgetPreparedNode, context: HanlinWidgetActionContext)
    case failure(String)

    /// Retain historical whole-widget navigation only when it cannot cover an
    /// interactive control. Native engines always route through their own links.
    public var passiveLegacyURL: URL? {
        guard case let .legacy(widget) = self, widget.engine == .legacy,
              !Self.containsButton(widget.root) else { return nil }
        return widget.deepLink
    }

    private static func containsButton(_ node: HanlinScriptUINode) -> Bool {
        node.kind == .button || node.children.contains(where: containsButton)
    }
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
        return try HanlinValue(jsonValue: HanlinJSONValue.decodeCanonicalJSON(data, limits: .unbounded))
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
    private static let renderLogger = Logger(subsystem: "com.hanlin.ai", category: "WidgetRender")

    /// Observe only a fallback that has already passed the existing cache checks.
    /// Length-prefixed identity fields are hashed; no names, settings, props,
    /// authored output or error content are written to the system log.
    private static func recordRetainedExpoRender(
        snapshot: HanlinScriptExtensionSnapshot, widget: HanlinScriptWidgetSnapshot,
        instance: HanlinWidgetInstance, programSHA256: String, stateRevision: UInt64
    ) {
        guard let retained = snapshot.widgetLastSuccessfulRenders.first(where: {
            $0.matches(widget: widget, instance: instance, programSHA256: programSHA256)
        }) else { return }
        let identity = widget.identity
        let fields = [identity.installedPackageID.rawValue, identity.packageID.rawValue,
                      String(identity.generation), identity.entrypointID, identity.variantID]
        let material = fields.map { "\($0.utf8.count):\($0)" }.joined()
        let identitySHA256 = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
        renderLogger.error("widget_render_retained v=1 engine=expo identitySHA256=\(identitySHA256, privacy: .public) generation=\(identity.generation) family=\(widget.family, privacy: .public) programSHA256=\(programSHA256, privacy: .public) stateRevision=\(stateRevision) renderSHA256=\(retained.renderSHA256, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    public static func prepare(store: HanlinScriptExtensionStore, entityID: String, family: String) -> HanlinPreparedWidget {
        do {
          var prepared = HanlinPreparedWidget.failure("Widget preparation did not finish")
          try store.update { snapshot in
            guard let snapshot,
                  let widget = snapshot.widgets.first(where: { widget in
                      HanlinWidgetInstance(identity: widget.identity, engine: widget.engine, displayName: widget.displayName).entityID == entityID
                          && widget.family == family
                  }) else {
                      if let snapshot, snapshot.widgets.contains(where: { widget in
                          HanlinWidgetInstance(identity: widget.identity, engine: widget.engine, displayName: widget.displayName).entityID == entityID
                      }) {
                          throw HanlinScriptWidgetError("This widget does not support the \(family) size.")
                      }
                      throw HanlinScriptWidgetError("The selected widget is unavailable, disabled or belongs to an older generation.")
                  }
            if case let .malformed(reason) = widget.payload { throw HanlinScriptWidgetError(reason) }
            guard !snapshot.inactiveWidgetInstallations.contains(widget.identity.installedPackageID.rawValue) else { throw HanlinScriptWidgetError("Widget package is being updated or is disabled.") }
            guard widget.validUntil > .now else { throw HanlinScriptWidgetError("The widget snapshot has expired. Open Hanlin to republish it.") }
            if widget.engine == .legacy { prepared = .legacy(widget); return snapshot }
            guard let instance = snapshot.widgetInstances.first(where: { $0.identity == widget.identity && $0.engine == widget.engine }) else {
                throw HanlinScriptWidgetError("This widget instance is no longer active.")
            }
            let (program, digest) = try store.loadProgram(for: widget)
            let state = snapshot.widgetStates.first { $0.identity == widget.identity && $0.engine == widget.engine }
            guard state == nil || state?.artifactSHA256 == digest else { throw HanlinWidgetActionError.staleArtifact }
            var environment: [String: HanlinValue] = ["widgetFamily": .string(family), "family": .string(family),
                "timestamp": .number(Date.now.timeIntervalSince1970 * 1_000)]
            environment["settings"] = try HanlinWidgetJSON.value(instance.settings.mapValues { $0.toAny() })
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
                let node: HanlinValue
                do {
                    let rendered = try HanlinExpoWidgetsRuntime.shared.render(layout: program.javaScript,
                        props: props.mapValues { $0.toAny() }, environment: environment.mapValues { $0.toAny() }).get()
                    node = try HanlinWidgetJSON.value(rendered)
                } catch {
                    guard let cached = try? store.lastSuccessfulWidgetNode(in: snapshot, widget: widget,
                        instance: instance, programSHA256: digest), case let .expo(previous) = cached else { throw error }
                    prepared = .expo(node: previous, context: context)
                    recordRetainedExpoRender(snapshot: snapshot, widget: widget, instance: instance,
                        programSHA256: digest, stateRevision: state?.revision ?? 0)
                    return snapshot
                }
                prepared = .expo(node: node, context: context)
                let record = try store.storeSuccessfulWidgetNode(.expo(node), widget: widget,
                    instance: instance, programSHA256: digest)
                return snapshot.retainingSuccessfulWidgetRender(record)
            }
            let result: HanlinScriptWidgetExecution
            do {
                result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: state?.values ?? [:], environment: environment,
                    nativeRoot: store.root.appendingPathComponent("ScriptWidgetOriginal/v1", isDirectory: true),
                    nativeIdentity: try HanlinScriptWidgetRuntime.nativeIdentity(widget.identity, artifactSHA256: digest))
            } catch {
                guard let cached = try? store.lastSuccessfulWidgetNode(in: snapshot, widget: widget,
                    instance: instance, programSHA256: digest), case let .scriptwidget(previous) = cached else { throw error }
                prepared = .scriptwidget(node: previous, context: context)
                return snapshot
            }
            prepared = .scriptwidget(node: result.node, context: context)
            let record = try store.storeSuccessfulWidgetNode(.scriptwidget(result.node), widget: widget,
                instance: instance, programSHA256: digest)
            // ScriptWidget scripts can populate typed storage during timeline
            // preparation too. Publish those writes in this same transaction;
            // a concurrent AppIntent cannot be overwritten by an old read.
            guard result.values != (state?.values ?? [:]) else { return snapshot.retainingSuccessfulWidgetRender(record) }
            guard (state?.revision ?? 0) < UInt64.max else { throw HanlinWidgetActionError.invalidState }
            let updated = HanlinWidgetInstanceState(identity: widget.identity, engine: widget.engine, artifactSHA256: digest,
                revision: (state?.revision ?? 0) + 1, values: result.values, committedNonces: state?.committedNonces ?? [])
            return snapshot.retainingSuccessfulWidgetRender(record,
                states: snapshot.widgetStates.filter { !($0.identity == widget.identity && $0.engine == widget.engine) } + [updated])
          }
          return prepared
        } catch { return .failure("Widget preparation failed: \(error)") }
    }
}
