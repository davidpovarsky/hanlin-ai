import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public struct HanlinWidgetActionCommand: Codable, Hashable, Sendable {
    public let context: HanlinWidgetActionContext
    public let actionID: String
    public let target: String
    public let nonce: String
    public var desiredValue: Bool?

    public init(context: HanlinWidgetActionContext, actionID: String, target: String? = nil,
                nonce: String = "", desiredValue: Bool? = nil) {
        self.context = context
        self.actionID = actionID
        self.target = target ?? actionID
        self.nonce = nonce
        self.desiredValue = desiredValue
    }
}

public enum HanlinWidgetActionError: Error, Equatable, Sendable {
    case invalidIdentity, inactiveInstance, staleArtifact, undeclaredAction, missingValue, noCallback, invalidState
}

public struct HanlinWidgetActionReceipt: Sendable {
    public let revision: UInt64
    public let applied: Bool
}

public enum HanlinWidgetActionExecutor {
    public static let widgetKind = "com.hanlin.scripting.widget"

    public static func perform(_ command: HanlinWidgetActionCommand, store: HanlinScriptExtensionStore) throws -> HanlinWidgetActionReceipt {
        let context = command.context
        let identity = context.identity
        // Even decoded wire identities are validated here, before file or state writes.
        _ = try HanlinInstalledPackageID(validating: identity.installedPackageID.rawValue)
        _ = try HanlinPackageID(validating: identity.packageID.rawValue)
        guard identity.generation > 0, !identity.entrypointID.isEmpty, !identity.variantID.isEmpty,
              identity.entrypointID.utf8.count <= 128, identity.variantID.utf8.count <= 128,
              context.engine != .legacy, HanlinWidgetProgram.isSHA256(context.artifactSHA256),
              command.nonce.utf8.count <= 128 else { throw HanlinWidgetActionError.invalidIdentity }
        // Native WidgetKit does not expose a per-tap stable retry identifier.
        // Empty native nonces identify separate invocations; explicit callers can
        // supply a nonce for durable replay protection within the receipt window.
        let nonce = command.nonce.isEmpty ? UUID().uuidString : command.nonce
        var receipt = HanlinWidgetActionReceipt(revision: 0, applied: false)
        try store.update { current in
            guard let current,
                  !current.inactiveWidgetInstallations.contains(identity.installedPackageID.rawValue),
                  current.widgetInstances.contains(where: { $0.identity == identity && $0.engine == context.engine }),
                  let widget = current.widgets.first(where: { $0.identity == identity && $0.engine == context.engine && $0.family == context.family }),
                  widget.validUntil > .now else { throw HanlinWidgetActionError.inactiveInstance }
            let (program, digest) = try store.loadProgram(for: widget)
            guard digest == context.artifactSHA256 else { throw HanlinWidgetActionError.staleArtifact }
            guard let action = program.actions.first(where: { $0.id == command.actionID }) else { throw HanlinWidgetActionError.undeclaredAction }
            let old = current.widgetStates.first { $0.identity == identity && $0.engine == context.engine }
            guard old == nil || old?.artifactSHA256 == digest else { throw HanlinWidgetActionError.staleArtifact }
            var state = old ?? .init(identity: identity, engine: context.engine, artifactSHA256: digest, values: {
                if case let .expo(descriptor) = widget.payload { return descriptor.props ?? [:] }
                return [:]
            }())
            if state.committedNonces.contains(nonce) {
                receipt = .init(revision: state.revision, applied: false)
                return current
            }
            var environment = context.environment
            environment["family"] = .string(widget.family)
            environment["widgetFamily"] = .string(widget.family)
            environment["timestamp"] = .number(Date.now.timeIntervalSince1970 * 1_000)
            if action.kind != .reload {
                switch context.engine {
                case .expo:
                    guard action.kind == .expoCallback, command.target == action.id else { throw HanlinWidgetActionError.undeclaredAction }
                    environment["target"] = .string(command.target)
                    let result = try HanlinExpoWidgetsRuntime.shared.handlePress(layout: program.javaScript,
                        props: state.values.mapValues { $0.toAny() }, environment: environment.mapValues { $0.toAny() }).get()
                    guard let result else { throw HanlinWidgetActionError.noCallback }
                    state.values.merge(try HanlinWidgetJSON.dictionary(result)) { _, new in new }
                case .scriptwidget:
                    guard action.kind == .function || action.kind == .setValue else { throw HanlinWidgetActionError.undeclaredAction }
                    if action.kind == .setValue {
                        guard let key = action.stateKey, let value = command.desiredValue else { throw HanlinWidgetActionError.missingValue }
                        state.values[key] = .bool(value)
                    }
                    let execution = try HanlinScriptWidgetRuntime.shared.run(program: program, values: state.values,
                        environment: environment, actionID: action.handler == nil ? nil : action.id, actionValue: command.desiredValue)
                    state.values = execution.values
                case .legacy: throw HanlinWidgetActionError.invalidIdentity
                }
            }
            guard state.revision < UInt64.max, try JSONEncoder().encode(state.values).count <= 256 * 1_024 else { throw HanlinWidgetActionError.invalidState }
            state.revision += 1
            state.committedNonces = Array((state.committedNonces + [nonce]).suffix(128))
            var states = current.widgetStates.filter { !($0.identity == identity && $0.engine == context.engine) }
            states.append(state)
            receipt = .init(revision: state.revision, applied: true)
            return current.replacing(states: states)
        }
        return receipt
    }
}
