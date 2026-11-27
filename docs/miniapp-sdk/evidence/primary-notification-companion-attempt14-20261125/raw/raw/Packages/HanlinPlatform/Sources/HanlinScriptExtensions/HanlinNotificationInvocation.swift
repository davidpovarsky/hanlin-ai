import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore

/// Notification ingress only persists data. The existing foreground Host
/// validates the current installation and executes its declared action.
public enum HanlinNotificationInvocation {
    public static func command(for event: HanlinNotificationEvent) throws -> HanlinScriptResumeCommand {
        .init(id: event.id, createdAt: event.createdAt, invocation: .init(
            identity: event.identity, entityID: event.actionID.rawValue,
            parameters: try HanlinValue(jsonValue: event.parameters), continueInForeground: true,
            delivery: .init(appID: event.appID, source: .notification, expiresAt: event.expiresAt,
                            expectedResult: .value, userGesturePresent: false, canPresentUI: false)))
    }

    /// A repeated identical event reads the original receipt, including a
    /// terminal result. The canonical queue rejects an ID with changed content.
    @discardableResult
    public static func enqueue(_ event: HanlinNotificationEvent,
                               in store: HanlinScriptExtensionStore,
                               now: Date = .now) throws -> HanlinInvocationReceipt {
        let command = try command(for: event)
        if try store.command(for: event.id) != nil {
            // Recheck immutable command equality, never replace an existing
            // lease/result merely because the catalog changed after delivery.
            try store.enqueue(command)
        } else {
            // The published catalog can lag installation or first launch.
            // Retain every structurally valid envelope in the canonical queue;
            // only the restored live Host may decide target/generation validity.
            try store.enqueue(command)
            if event.expiresAt <= now {
                // The existing queue records expiry without starting a handler
                // or consuming an action attempt. An expired event never runs.
                _ = try store.claim(event.id, now: now)
            }
        }
        guard let receipt = try store.receipt(for: event.id) else {
            throw HanlinInvocationQueueError.missingCommand
        }
        return receipt
    }

    /// Call after restoring the live store, immediately before Host dispatch.
    /// The notification cannot select a different generation, an undeclared
    /// action, a rich-notification view or a legacy scripting engine.
    public static func validateTarget(_ command: HanlinScriptResumeCommand,
                                      packages: [HanlinStoredPackageSnapshot], hostIsActive: Bool) throws {
        guard command.invocation.delivery?.source == .notification,
              command.invocation.continueInForeground,
              command.invocation.delivery?.userGesturePresent == false,
              command.invocation.delivery?.canPresentUI == false else {
            throw HanlinInvocationDispatchError(.failed, .invalidEnvelope)
        }
        guard hostIsActive else { throw HanlinInvocationNotStarted() }
        let identity = command.invocation.identity
        guard let package = packages.first(where: {
            $0.record.installedPackageID == identity.installedPackageID
                && $0.record.packageID == identity.packageID
        }) else { throw HanlinInvocationDispatchError(.stale, .invalidTarget) }
        guard package.enabled else { throw HanlinInvocationDispatchError(.stale, .disabledPackage) }
        guard package.record.activeGeneration == identity.generation else {
            throw HanlinInvocationDispatchError(.stale, .staleGeneration)
        }
        guard command.invocation.delivery?.appID == package.appID,
              let entrypoint = package.entrypoints.first(where: {
                  $0.id == identity.entrypointID && $0.kind == .appIntent
                      && ($0.runtimeProfile == .hanlinExpo || $0.runtimeProfile == .hanlinNativeScript)
              }),
              let name = command.invocation.entityID,
              let actionID = try? HanlinActionID(validating: name),
              let descriptor = try? package.appDescriptor(),
              let action = descriptor.actions.first(where: { $0.id == actionID }),
              entrypoint.exportedSymbol == nil || entrypoint.exportedSymbol == name,
              entrypoint.runtimePolicyID != "prepared-foreground-action-v1"
                || action.handler == entrypoint.sourcePath else {
            throw HanlinInvocationDispatchError(.failed, .unsupportedEntrypoint)
        }
    }
}
