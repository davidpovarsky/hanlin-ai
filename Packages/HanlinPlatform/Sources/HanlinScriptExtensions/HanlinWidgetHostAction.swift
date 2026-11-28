import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

/// The immutable origin remains separate from the target App Intent identity.
public struct HanlinWidgetInvocationOrigin: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let engine: HanlinWidgetEngine
    public let artifactSHA256: String
    public let family: String
    public let actionID: String
    /// Distinguishes omitted/default parameters from an explicit value on retry.
    public let parametersSHA256: String?

    public init(identity: HanlinScriptExtensionIdentity, engine: HanlinWidgetEngine,
                artifactSHA256: String, family: String, actionID: String, parametersSHA256: String? = nil) {
        self.identity = identity
        self.engine = engine
        self.artifactSHA256 = artifactSHA256
        self.family = family
        self.actionID = actionID
        self.parametersSHA256 = parametersSHA256
    }
}

/// Admission uses the existing App Group transaction and canonical command queue.
/// It never invokes JavaScript, Node or a native runtime inside the extension.
public enum HanlinWidgetHostActionExecutor {
    public static func enqueue(_ command: HanlinWidgetActionCommand,
                               store: HanlinScriptExtensionStore) throws -> HanlinScriptResumeCommand {
        let context = command.context
        guard context.presentation == nil, context.environment["presentation"] == nil,
              command.controlID == nil, command.desiredValue == nil,
              command.target == command.actionID, command.nonce.utf8.count <= 128 else {
            throw HanlinWidgetActionError.undeclaredAction
        }
        let source: HanlinInvocationDelivery.Source =
            context.environment["liveActivity"] == .bool(true) ? .liveActivity : .widget
        let origin = HanlinWidgetInvocationOrigin(identity: context.identity, engine: context.engine,
            artifactSHA256: context.artifactSHA256, family: context.family, actionID: command.actionID,
            parametersSHA256: try parametersDigest(command.parameters))
        let id = try invocationID(origin: origin, source: source, nonce: command.nonce)
        return try store.enqueueValidated(id) { snapshot, previous in
            if let previous {
                // An exact redelivery reads the original receipt even after
                // disable/removal. It cannot reset a lease or execute a result again.
                guard previous.invocation.delivery?.source == source,
                      previous.invocation.delivery?.widgetOrigin == origin else {
                    throw HanlinInvocationQueueError.duplicateIdentity
                }
                return previous
            }
            let target = try resolve(origin: origin, snapshot: snapshot, store: store)
            let parameters = try command.parameters
                ?? target.action.parameters.map { try HanlinValue(jsonValue: $0) } ?? .null
            let createdAt = previous?.createdAt ?? .now
            let invocation = HanlinScriptIntentInvocation(identity: target.entity.identity,
                entityID: target.action.actionName, parameters: parameters, continueInForeground: true,
                delivery: .init(appID: target.appID, source: source,
                    expiresAt: previous?.invocation.delivery?.expiresAt
                        ?? createdAt.addingTimeInterval(HanlinInvocationDelivery.maximumLifetime),
                    userGesturePresent: true, canPresentUI: true, widgetOrigin: origin))
            return .init(id: id, createdAt: createdAt, invocation: invocation)
        }
    }


    /// The original native-node ActivityKit renderer has a declared action
    /// identity, not a WidgetProgram. Keep that source distinction explicit.
    public static func enqueueLiveActivity(identity: HanlinScriptExtensionIdentity, actionName: String,
                                           parameters: HanlinValue, store: HanlinScriptExtensionStore) throws
        -> HanlinScriptResumeCommand {
        let id = UUID()
        return try store.enqueueValidated(id) { snapshot, _ in
            let entity = try publishedEntity(identity: identity, actionName: actionName, snapshot: snapshot)
            let now = Date.now
            let delivery: HanlinInvocationDelivery?
            if entity.hostActionHandler?.isEmpty == false {
                guard let appID = entity.appID else {
                    throw HanlinWidgetActionError.undeclaredAction
                }
                delivery = .init(appID: appID, source: .liveActivity,
                    expiresAt: now.addingTimeInterval(HanlinInvocationDelivery.maximumLifetime),
                    userGesturePresent: true, canPresentUI: true)
            } else {
                // A presentation-only placeholder is not a registered handler.
                guard entity.nativePresentation == nil else { throw HanlinWidgetActionError.undeclaredAction }
                // Known published legacy/compiled intents retain their original
                // envelope. This is compatibility, not a new native Host claim.
                delivery = nil
            }
            return .init(id: id, createdAt: now, invocation: .init(identity: identity,
                entityID: actionName, parameters: parameters, continueInForeground: true, delivery: delivery))
        }
    }

    public static func validateLiveActivityTarget(_ command: HanlinScriptResumeCommand,
                                                  store: HanlinScriptExtensionStore) throws {
        guard let delivery = command.invocation.delivery, delivery.source == .liveActivity,
              delivery.widgetOrigin == nil, let actionName = command.invocation.entityID else {
            throw HanlinInvocationDispatchError(.failed, .invalidEnvelope)
        }
        do {
            try store.update { snapshot in
                let entity = try publishedEntity(identity: command.invocation.identity,
                    actionName: actionName, snapshot: snapshot)
                guard entity.appID == delivery.appID, entity.hostActionHandler?.isEmpty == false,
                      let snapshot else {
                    throw HanlinWidgetActionError.undeclaredAction
                }
                return snapshot
            }
        } catch is HanlinWidgetActionError {
            throw HanlinInvocationDispatchError(.stale, .invalidTarget)
        }
    }

    private static func publishedEntity(identity: HanlinScriptExtensionIdentity, actionName: String,
                                        snapshot: HanlinScriptExtensionSnapshot?) throws
        -> HanlinScriptIntentEntityRecord {
        _ = try HanlinInstalledPackageID(validating: identity.installedPackageID.rawValue)
        _ = try HanlinPackageID(validating: identity.packageID.rawValue)
        guard !identity.entrypointID.isEmpty, !identity.variantID.isEmpty, let snapshot,
              !snapshot.inactiveWidgetInstallations.contains(identity.installedPackageID.rawValue) else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        let candidates = snapshot.intentEntities.filter { $0.identity == identity && $0.id == actionName }
        guard candidates.count == 1, let entity = candidates.first else {
            throw HanlinWidgetActionError.undeclaredAction
        }
        return entity
    }

    /// The Host repeats origin and target validation after suspension/restart,
    /// before its existing action dispatcher can execute package code.
    public static func validateCurrentOrigin(_ command: HanlinScriptResumeCommand,
                                             store: HanlinScriptExtensionStore) throws {
        guard let delivery = command.invocation.delivery,
              delivery.source == .widget || delivery.source == .liveActivity,
              let origin = delivery.widgetOrigin else {
            throw HanlinInvocationDispatchError(.failed, .invalidEnvelope)
        }
        do {
            try store.update { snapshot in
                let target = try resolve(origin: origin, snapshot: snapshot, store: store)
                guard target.entity.identity == command.invocation.identity,
                      target.action.actionName == command.invocation.entityID,
                      target.appID == delivery.appID else {
                    throw HanlinWidgetActionError.undeclaredAction
                }
                guard let snapshot else { throw HanlinWidgetActionError.inactiveInstance }
                return snapshot
            }
        } catch let error as HanlinWidgetActionError {
            throw HanlinInvocationDispatchError(.stale,
                error == .inactiveInstance || error == .staleArtifact ? .staleGeneration : .invalidTarget)
        }
    }

    private static func resolve(origin: HanlinWidgetInvocationOrigin,
                                snapshot: HanlinScriptExtensionSnapshot?,
                                store: HanlinScriptExtensionStore) throws
        -> (action: HanlinWidgetHostAction, entity: HanlinScriptIntentEntityRecord, appID: HanlinAppID) {
        let identity = origin.identity
        _ = try HanlinInstalledPackageID(validating: identity.installedPackageID.rawValue)
        _ = try HanlinPackageID(validating: identity.packageID.rawValue)
        guard identity.generation > 0, !identity.entrypointID.isEmpty, !identity.variantID.isEmpty,
              identity.entrypointID.utf8.count <= 128, identity.variantID.utf8.count <= 128,
              origin.engine == .expo || origin.engine == .scriptwidget,
              HanlinWidgetProgram.isSHA256(origin.artifactSHA256) else {
            throw HanlinWidgetActionError.invalidIdentity
        }
        guard let snapshot,
              !snapshot.inactiveWidgetInstallations.contains(identity.installedPackageID.rawValue),
              snapshot.widgetInstances.contains(where: { $0.identity == identity && $0.engine == origin.engine }),
              let widget = snapshot.widgets.first(where: {
                  $0.identity == identity && $0.engine == origin.engine && $0.family == origin.family
              }), widget.validUntil > .now else { throw HanlinWidgetActionError.inactiveInstance }
        // loadProgram reads and verifies immutable artifact bytes without taking
        // the transaction lock again; the snapshot and admission remain atomic.
        let (program, digest) = try store.loadProgram(for: widget)
        guard digest == origin.artifactSHA256,
              snapshot.widgetStates.first(where: { $0.identity == identity && $0.engine == origin.engine })
                .map({ $0.artifactSHA256 == digest }) ?? true else {
            throw HanlinWidgetActionError.staleArtifact
        }
        guard let declaration = program.actions.first(where: { $0.id == origin.actionID }),
              declaration.kind == .hostAction, declaration.handler == nil, declaration.stateKey == nil,
              let action = declaration.hostAction else { throw HanlinWidgetActionError.undeclaredAction }
        let candidates = snapshot.intentEntities.filter {
            $0.identity.installedPackageID == identity.installedPackageID &&
            $0.identity.packageID == identity.packageID &&
            $0.identity.generation == identity.generation &&
            $0.identity.entrypointID == action.entrypointID && $0.identity.variantID == "default" &&
            $0.id == action.actionName &&
            $0.hostActionHandler?.isEmpty == false && $0.appID != nil
        }
        guard candidates.count == 1, let entity = candidates.first, let appID = entity.appID else {
            throw HanlinWidgetActionError.undeclaredAction
        }
        return (action, entity, appID)
    }

    private static func parametersDigest(_ parameters: HanlinValue?) throws -> String {
        struct Request: Encodable { let parameters: HanlinValue? }
        let bytes = try HanlinScriptExtensionStore.encoded(Request(parameters: parameters))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func invocationID(origin: HanlinWidgetInvocationOrigin,
                                     source: HanlinInvocationDelivery.Source, nonce: String) throws -> UUID {
        // WidgetKit does not supply a stable tap retry ID. Empty means a new
        // invocation; explicit nonces retain the same durable receipt.
        guard !nonce.isEmpty else { return UUID() }
        struct Identity: Encodable {
            let origin: HanlinWidgetInvocationOrigin
            let source: HanlinInvocationDelivery.Source
            let nonce: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Keep the nonce identity independent of parameters so a conflicting
        // request is rejected rather than silently receiving a fresh invocation.
        let stableOrigin = HanlinWidgetInvocationOrigin(identity: origin.identity, engine: origin.engine,
            artifactSHA256: origin.artifactSHA256, family: origin.family, actionID: origin.actionID)
        var bytes = Array(SHA256.hash(data: try encoder.encode(Identity(origin: stableOrigin, source: source, nonce: nonce))).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80 // RFC 9562 custom UUID.
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// A weak, product/store-bound wake for the app process selected by the intent.
/// Durable queue admission is independent of whether a Host is ready to drain.
@MainActor
public enum HanlinWidgetHostActionContinuation {
    private final class Registration {
        weak var owner: AnyObject?
        let drain: @MainActor @Sendable () async -> Void
        init(owner: AnyObject, drain: @escaping @MainActor @Sendable () async -> Void) {
            self.owner = owner
            self.drain = drain
        }
    }
    private static var registrations: [String: Registration] = [:]

    public static func register(owner: AnyObject, storeRoot: URL,
                                drain: @escaping @MainActor @Sendable () async -> Void) {
        registrations[key(storeRoot)] = Registration(owner: owner, drain: drain)
    }

    public static func resume(storeRoot: URL) async {
        let key = key(storeRoot)
        guard let registration = registrations[key], registration.owner != nil else {
            registrations[key] = nil
            return
        }
        await registration.drain()
    }

    private static func key(_ root: URL) -> String {
        // Callers pass store.root, whose existing canonicalManagedRoot policy
        // stays stable before/after creation and never follows the managed leaf.
        root.path(percentEncoded: false)
    }
}
