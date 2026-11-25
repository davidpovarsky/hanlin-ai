import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
@preconcurrency import HanlinScriptWidgetOriginal

public typealias HanlinScriptWidgetControlKind = HanlinOriginalScriptWidgetControls.Control.Kind

public struct HanlinScriptWidgetControlRecord: Hashable, Sendable {
    public let id: String
    public let controlID: String
    public let kind: HanlinScriptWidgetControlKind
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let isOn: Bool
    public let actionID: String
    public let context: HanlinWidgetActionContext
}

public struct HanlinScriptWidgetControlExecution: Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let receipt: HanlinWidgetActionReceipt
}

/// The original control picker reads only the current host publication. Archived
/// original runtime directories never become independent control installations.
public enum HanlinScriptWidgetControlCatalog {
    public static let buttonKind = "ScriptWidget.Button"
    public static let toggleKind = "ScriptWidget.Toggle"

    public static func controls(type: HanlinScriptWidgetControlKind,
                                store: HanlinScriptExtensionStore) throws -> [HanlinScriptWidgetControlRecord] {
        guard let snapshot = try store.load() else { return [] }
        var result: [HanlinScriptWidgetControlRecord] = []
        for instance in snapshot.widgetInstances where instance.engine == .scriptwidget {
            guard !snapshot.inactiveWidgetInstallations.contains(instance.identity.installedPackageID.rawValue),
                  let widget = snapshot.widgets.filter({
                      $0.identity == instance.identity && $0.engine == .scriptwidget && $0.validUntil > .now
                  }).sorted(by: { $0.family < $1.family }).first else { continue }
            let (program, digest) = try store.loadProgram(for: widget)
            guard let data = program.resources["widget.json"] else { continue }
            let original = try HanlinOriginalScriptWidgetControls.read(data)
            let state = snapshot.widgetStates.first { $0.identity == instance.identity && $0.engine == .scriptwidget }
            guard state == nil || state?.artifactSHA256 == digest else { continue }
            let context = HanlinWidgetActionContext(identity: instance.identity, engine: .scriptwidget,
                artifactSHA256: digest, family: widget.family, actions: program.actions)
            for control in original.controls where control.kind == type {
                let expected = HanlinWidgetActionDeclaration(id: control.preparedActionID,
                    kind: control.kind == .toggle ? .setValue : .function,
                    handler: control.handler, stateKey: control.stateKey)
                guard program.actions.contains(expected) else { continue }
                let labels = [widget.displayName, instance.identity.installedPackageID.rawValue,
                              control.subtitle].compactMap { $0 }.filter { !$0.isEmpty }
                result.append(.init(id: identifier(store: store, identity: instance.identity, controlID: control.id),
                    controlID: control.id, kind: type, title: control.title,
                    subtitle: labels.joined(separator: " · "), systemImage: control.systemImage,
                    isOn: control.stateKey.map { bool(state?.values[$0]) } ?? false,
                    actionID: control.preparedActionID, context: context))
            }
        }
        return result.sorted {
            ($0.subtitle, $0.title, $0.id) < ($1.subtitle, $1.title, $1.id)
        }
    }

    public static func resolve(identifier: String, type: HanlinScriptWidgetControlKind,
                               store: HanlinScriptExtensionStore) throws -> HanlinScriptWidgetControlRecord? {
        try controls(type: type, store: store).first { $0.id == identifier }
    }

    public static func perform(identifier: String, type: HanlinScriptWidgetControlKind, value: Bool? = nil,
                               nonce: String = "", store: HanlinScriptExtensionStore) throws -> HanlinScriptWidgetControlExecution {
        guard let control = try resolve(identifier: identifier, type: type, store: store) else {
            throw HanlinWidgetActionError.inactiveInstance
        }
        if type == .toggle && value == nil { throw HanlinWidgetActionError.missingValue }
        if type == .button && value != nil { throw HanlinWidgetActionError.undeclaredAction }
        let command = HanlinWidgetActionCommand(context: control.context, actionID: control.actionID,
            nonce: nonce, desiredValue: value, controlID: control.controlID)
        let receipt = try HanlinWidgetActionExecutor.perform(command, store: store)
        return .init(identity: control.context.identity, receipt: receipt)
    }

    /// Stable across generation upgrades of one installation/variant. The exact
    /// current generation and artifact are re-resolved and checked when invoked.
    private static func identifier(store: HanlinScriptExtensionStore,
                                   identity: HanlinScriptExtensionIdentity, controlID: String) -> String {
        let fields = [store.root.resolvingSymlinksInPath().standardizedFileURL.path,
                      identity.installedPackageID.rawValue, identity.packageID.rawValue,
                      identity.entrypointID, identity.variantID, controlID]
        let bytes = fields.map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
        return "scriptwidget-control-v1:" + SHA256.hash(data: Data(bytes.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func bool(_ value: HanlinValue?) -> Bool {
        switch value {
        case let .bool(value): return value
        case let .string(value): return value == "true" || value == "1"
        default: return false
        }
    }
}
