import Foundation
import HanlinPlatformContracts

/// The original ScriptWidget tree stays in the shared artifact store. ActivityKit
/// carries its immutable reference, rather than copying an arbitrary view tree
/// into the system's small content-state payload.
public struct HanlinScriptWidgetLiveActivitySnapshot: Codable, Hashable, Sendable {
    public let node: HanlinScriptWidgetPreparedNode
    public let dynamicIsland: HanlinScriptWidgetDynamicIsland?
    public let context: HanlinWidgetActionContext
    public init(node: HanlinScriptWidgetPreparedNode, dynamicIsland: HanlinScriptWidgetDynamicIsland?,
                context: HanlinWidgetActionContext) {
        self.node = node
        self.dynamicIsland = dynamicIsland
        self.context = context
    }
}

public struct HanlinScriptWidgetLiveActivityAttributes: Codable, Hashable, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let revision: UInt64
        public let title: String
        public let snapshotRef: String
        public let snapshotSHA256: String
        public init(revision: UInt64, title: String, snapshotRef: String, snapshotSHA256: String) {
            self.revision = revision
            self.title = title
            self.snapshotRef = snapshotRef
            self.snapshotSHA256 = snapshotSHA256
        }
    }
    public let identity: HanlinScriptExtensionIdentity
    public let entityID: String
    public let family: String
    public init(identity: HanlinScriptExtensionIdentity, entityID: String, family: String) {
        self.identity = identity
        self.entityID = entityID
        self.family = family
    }
}

public enum HanlinScriptWidgetLiveActivityPreparation {
    public static func prepare(store: HanlinScriptExtensionStore, entityID: String,
                               family: String, values: [String: HanlinValue] = [:],
                               revision: UInt64, title: String, executionControl: HanlinScriptWidgetExecutionControl = .init()) throws
        -> (attributes: HanlinScriptWidgetLiveActivityAttributes, state: HanlinScriptWidgetLiveActivityAttributes.ContentState) {
        var output: (HanlinScriptWidgetLiveActivityAttributes, HanlinScriptWidgetLiveActivityAttributes.ContentState)?
        try executionControl.checkCancellation()
        try store.update { current in
            try executionControl.checkCancellation()
            guard let current,
                  let instance = current.widgetInstances.first(where: {
                      $0.entityID == entityID && $0.engine == .scriptwidget
                  }),
                  !current.inactiveWidgetInstallations.contains(instance.identity.installedPackageID.rawValue),
                  let widget = current.widgets.first(where: {
                      $0.identity == instance.identity && $0.engine == .scriptwidget && $0.family == family
                  }), widget.validUntil > .now else { throw HanlinWidgetActionError.inactiveInstance }
            let identity = instance.identity
            let (program, digest) = try store.loadProgram(for: widget)
            let old = current.widgetStates.first { $0.identity == identity && $0.engine == .scriptwidget }
            guard old == nil || old?.artifactSHA256 == digest else { throw HanlinWidgetActionError.staleArtifact }
            var stateValues = old?.values ?? [:]
            stateValues.merge(values) { _, new in new }
            var environment: [String: HanlinValue] = [:]
            if case let .scriptwidget(descriptor) = widget.payload { environment = descriptor.environment ?? [:] }
            environment["family"] = .string(family)
            environment["widgetFamily"] = .string(family)
            // The presentation context belongs only to snippet/translation surfaces.
            environment["presentation"] = nil
            environment["liveActivity"] = .bool(true)
            environment["timestamp"] = .number(Date.now.timeIntervalSince1970 * 1_000)
            environment["settings"] = try HanlinWidgetJSON.value(instance.settings.mapValues { $0.toAny() })
            let execution = try HanlinScriptWidgetRuntime.shared.run(
                program: program, values: stateValues, environment: environment,
                nativeRoot: store.root.appendingPathComponent("ScriptWidgetOriginal/v1", isDirectory: true),
                nativeIdentity: try HanlinScriptWidgetRuntime.nativeIdentity(identity, artifactSHA256: digest), executionControl: executionControl)
            let resources = try store.materializeResources(program.resources, identity: identity)
            let context = HanlinWidgetActionContext(identity: identity, engine: .scriptwidget,
                artifactSHA256: digest, family: family, environment: environment,
                actions: program.actions, resources: resources)
            let prepared = HanlinScriptWidgetLiveActivitySnapshot(node: execution.node,
                dynamicIsland: execution.dynamicIsland, context: context)
            try executionControl.checkCancellation()
            let artifact = try store.storeArtifact(data: JSONEncoder().encode(prepared),
                installedPackageID: identity.installedPackageID, generation: identity.generation)
            output = (.init(identity: identity, entityID: entityID, family: family),
                      .init(revision: revision, title: title, snapshotRef: artifact.ref, snapshotSHA256: artifact.sha256))
            try executionControl.checkCancellation()
            guard execution.values != (old?.values ?? [:]) else { return current }
            guard (old?.revision ?? 0) < UInt64.max else { throw HanlinWidgetActionError.invalidState }
            let state = HanlinWidgetInstanceState(identity: identity, engine: .scriptwidget,
                artifactSHA256: digest, revision: (old?.revision ?? 0) + 1,
                values: execution.values, committedNonces: old?.committedNonces ?? [])
            return current.replacing(states: current.widgetStates.filter {
                !($0.identity == identity && $0.engine == .scriptwidget)
            } + [state])
        }
        guard let output else { throw HanlinWidgetActionError.inactiveInstance }
        return output
    }

    private static func currentWidget(attributes: HanlinScriptWidgetLiveActivityAttributes,
                                      in snapshot: HanlinScriptExtensionSnapshot) -> HanlinScriptWidgetSnapshot? {
        guard !snapshot.inactiveWidgetInstallations.contains(attributes.identity.installedPackageID.rawValue),
              snapshot.widgetInstances.contains(where: {
                  $0.entityID == attributes.entityID && $0.identity == attributes.identity && $0.engine == .scriptwidget
              }) else { return nil }
        return snapshot.widgets.first {
            $0.identity == attributes.identity && $0.engine == .scriptwidget &&
                $0.family == attributes.family && $0.validUntil > .now
        }
    }

    static func isActive(attributes: HanlinScriptWidgetLiveActivityAttributes,
                         in snapshot: HanlinScriptExtensionSnapshot) -> Bool {
        currentWidget(attributes: attributes, in: snapshot) != nil
    }

    public static func load(store: HanlinScriptExtensionStore,
                            attributes: HanlinScriptWidgetLiveActivityAttributes,
                            state: HanlinScriptWidgetLiveActivityAttributes.ContentState) throws
        -> HanlinScriptWidgetLiveActivitySnapshot {
        guard let current = try store.load(),
              let widget = currentWidget(attributes: attributes, in: current) else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        let (_, currentDigest) = try store.loadProgram(for: widget)
        let data = try store.loadVerifiedArtifact(ref: state.snapshotRef, sha256: state.snapshotSHA256,
            installedPackageID: attributes.identity.installedPackageID, generation: attributes.identity.generation)
        let prepared = try JSONDecoder().decode(HanlinScriptWidgetLiveActivitySnapshot.self, from: data)
        guard prepared.context.identity == attributes.identity, prepared.context.engine == .scriptwidget,
              prepared.context.family == attributes.family else { throw HanlinWidgetActionError.invalidIdentity }
        guard prepared.context.artifactSHA256 == currentDigest else { throw HanlinWidgetActionError.staleArtifact }
        return prepared
    }
}

#if os(iOS)
import ActivityKit

extension HanlinScriptWidgetLiveActivityAttributes: ActivityAttributes {}

public enum HanlinScriptWidgetLiveActivityController {
    public static func start(store: HanlinScriptExtensionStore, entityID: String, family: String,
                             title: String, values: [String: HanlinValue] = [:],
                             staleDate: Date? = nil, relevanceScore: Double = 0) async throws -> String {
        let executionControl = HanlinScriptWidgetExecutionControl()
        let prepared = try await executionControl.perform {
            try HanlinScriptWidgetLiveActivityPreparation.prepare(store: store,
                entityID: entityID, family: family, values: values, revision: 1, title: title, executionControl: executionControl)
        }
        try Task.checkCancellation()
        return try await MainActor.run {
            _ = try HanlinScriptWidgetLiveActivityPreparation.load(
                store: store, attributes: prepared.attributes, state: prepared.state)
            return try Activity.request(attributes: prepared.attributes,
                content: ActivityContent(state: prepared.state, staleDate: staleDate, relevanceScore: relevanceScore),
                pushType: nil).id
        }
    }

    public static func activityIDs(installedPackageID: String) -> [String] {
        Activity<HanlinScriptWidgetLiveActivityAttributes>.activities.filter {
            $0.attributes.identity.installedPackageID.rawValue == installedPackageID
        }.map(\.id)
    }

    public static func contains(systemActivityID: String, installedPackageID: String) -> Bool {
        activityIDs(installedPackageID: installedPackageID).contains(systemActivityID)
    }

    public static func update(store: HanlinScriptExtensionStore, systemActivityID: String,
                              installedPackageID: String, title: String? = nil,
                              values: [String: HanlinValue] = [:], staleDate: Date? = nil,
                              relevanceScore: Double = 0) async throws -> Bool {
        guard let activity = Activity<HanlinScriptWidgetLiveActivityAttributes>.activities.first(where: {
            $0.id == systemActivityID && $0.attributes.identity.installedPackageID.rawValue == installedPackageID
        }) else { return false }
        let attributes = activity.attributes
        let previous = activity.content.state
        guard previous.revision < UInt64.max else { throw HanlinWidgetActionError.invalidState }
        let executionControl = HanlinScriptWidgetExecutionControl()
        let prepared = try await executionControl.perform {
            try HanlinScriptWidgetLiveActivityPreparation.prepare(store: store,
                entityID: attributes.entityID, family: attributes.family, values: values,
                revision: previous.revision + 1, title: title ?? previous.title, executionControl: executionControl)
        }
        try Task.checkCancellation()
        guard prepared.attributes == attributes else { throw HanlinWidgetActionError.inactiveInstance }
        _ = try HanlinScriptWidgetLiveActivityPreparation.load(store: store, attributes: attributes, state: prepared.state)
        await activity.update(ActivityContent(state: prepared.state, staleDate: staleDate, relevanceScore: relevanceScore))
        return true
    }

    public static func end(store: HanlinScriptExtensionStore, systemActivityID: String,
                           installedPackageID: String, title: String? = nil,
                           values: [String: HanlinValue] = [:], dismissAfterSeconds: Double? = nil) async throws -> Bool {
        guard let activity = Activity<HanlinScriptWidgetLiveActivityAttributes>.activities.first(where: {
            $0.id == systemActivityID && $0.attributes.identity.installedPackageID.rawValue == installedPackageID
        }) else { return false }
        var finalState = activity.content.state
        if title != nil || !values.isEmpty {
            guard finalState.revision < UInt64.max else { throw HanlinWidgetActionError.invalidState }
            let attributes = activity.attributes
            let previous = finalState
            let executionControl = HanlinScriptWidgetExecutionControl()
            let prepared = try await executionControl.perform {
                try HanlinScriptWidgetLiveActivityPreparation.prepare(store: store,
                    entityID: attributes.entityID, family: attributes.family, values: values,
                    revision: previous.revision + 1, title: title ?? previous.title, executionControl: executionControl)
            }
            try Task.checkCancellation()
            guard prepared.attributes == attributes else { throw HanlinWidgetActionError.inactiveInstance }
            _ = try HanlinScriptWidgetLiveActivityPreparation.load(store: store, attributes: attributes, state: prepared.state)
            finalState = prepared.state
        }
        let dismissalPolicy: ActivityUIDismissalPolicy = if let dismissAfterSeconds {
            dismissAfterSeconds <= 0 ? .immediate : .after(.now.addingTimeInterval(dismissAfterSeconds))
        } else { .default }
        await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: dismissalPolicy)
        return true
    }

    /// End only activities whose immutable installed generation/variant ceased
    /// to be current. The current publication is the same catalog the widget reads.
    @discardableResult
    public static func reconcile(snapshot: HanlinScriptExtensionSnapshot) async -> Int {
        let inactive = Activity<HanlinScriptWidgetLiveActivityAttributes>.activities.filter {
            !HanlinScriptWidgetLiveActivityPreparation.isActive(attributes: $0.attributes, in: snapshot)
        }
        for activity in inactive { await activity.end(nil, dismissalPolicy: .immediate) }
        return inactive.count
    }

    @discardableResult
    public static func endActivities(store: HanlinScriptExtensionStore, identity: HanlinScriptExtensionIdentity) async throws -> Int {
        var count = 0
        for activity in Activity<HanlinScriptWidgetLiveActivityAttributes>.activities where activity.attributes.identity == identity {
            if try await end(store: store, systemActivityID: activity.id,
                installedPackageID: identity.installedPackageID.rawValue, dismissAfterSeconds: 0) { count += 1 }
        }
        return count
    }

    /// Original native button/toggle execution commits state first; the same
    /// declared program then supplies the next Lock Screen and island views.
    public static func refresh(store: HanlinScriptExtensionStore, identity: HanlinScriptExtensionIdentity) async throws {
        for activity in Activity<HanlinScriptWidgetLiveActivityAttributes>.activities where activity.attributes.identity == identity {
            _ = try await update(store: store, systemActivityID: activity.id,
                installedPackageID: identity.installedPackageID.rawValue,
                staleDate: activity.content.staleDate, relevanceScore: activity.content.relevanceScore)
        }
    }
}
#endif
