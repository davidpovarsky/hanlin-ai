import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public enum HanlinNativePresentationKind: String, Codable, Hashable, Sendable {
    case snippet, translationUI
}

public struct HanlinNativePresentationDescriptor: Codable, Hashable, Sendable {
    public let engine: HanlinWidgetEngine
    public let programRef: String
    public let programSHA256: String
    public let input: HanlinNativePresentationInput?

    public init(engine: HanlinWidgetEngine, programRef: String, programSHA256: String,
                input: HanlinNativePresentationInput? = nil) {
        self.engine = engine
        self.programRef = programRef
        self.programSHA256 = programSHA256
        self.input = input
    }
}

/// Each invocation has its own state, including two snippets from the same
/// package. The selected text is ordinary input, never part of a file path.
public struct HanlinNativePresentationRequest: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let kind: HanlinNativePresentationKind
    public let sessionID: UUID
    public let actionName: String?
    public let inputText: String
    public let parameters: HanlinValue
    public let allowsReplacement: Bool

    public init(identity: HanlinScriptExtensionIdentity, kind: HanlinNativePresentationKind,
                sessionID: UUID = UUID(), actionName: String? = nil, inputText: String = "",
                parameters: HanlinValue = .null, allowsReplacement: Bool = false) {
        self.identity = identity
        self.kind = kind
        self.sessionID = sessionID
        self.actionName = actionName
        self.inputText = inputText
        self.parameters = parameters
        self.allowsReplacement = allowsReplacement
    }
}

public struct HanlinNativePresentationEffect: Codable, Hashable, Sendable {
    public var expandsSheet = false
    public var finishRequested = false
    public var replacementText: String?
    public init() {}
}

public struct HanlinNativePresentationExecution: Sendable {
    public let prepared: HanlinPreparedWidget
    public let effect: HanlinNativePresentationEffect
    public let revision: UInt64
}

public enum HanlinNativePresentationError: Error, LocalizedError, Sendable {
    case unavailable, invalidRequest, invalidAction, staleProgram, invalidState
    public var errorDescription: String? {
        switch self {
        case .unavailable: "This native presentation is unavailable in the current installed package."
        case .invalidRequest: "The native presentation input could not be read."
        case .invalidAction: "The native presentation does not declare this action."
        case .staleProgram: "The native presentation changed. Open it again to use the current version."
        case .invalidState: "The native presentation returned invalid state."
        }
    }
}

/// Native execution uses the same product store, immutable artifacts, original
/// engines and serialized state transaction as widgets, without publishing an
/// artificial WidgetKit instance.
public enum HanlinNativePresentationExecutor {
    private struct State: Codable {
        let inputSHA256: String
        let artifactSHA256: String
        var revision: UInt64
        var values: [String: HanlinValue]
        var committedNonces: [String]
    }

    public static func descriptor(for request: HanlinNativePresentationRequest,
                                  in snapshot: HanlinScriptExtensionSnapshot) throws -> HanlinNativePresentationDescriptor {
        guard !snapshot.inactiveWidgetInstallations.contains(request.identity.installedPackageID.rawValue) else {
            throw HanlinNativePresentationError.unavailable
        }
        let descriptor: HanlinNativePresentationDescriptor?
        switch request.kind {
        case .snippet:
            descriptor = snapshot.intentEntities.first {
                $0.identity == request.identity && $0.id == request.actionName
            }?.nativePresentation
        case .translationUI:
            descriptor = snapshot.translationApps.first { $0.identity == request.identity }?.nativePresentation
        }
        guard let descriptor, descriptor.engine != .legacy else { throw HanlinNativePresentationError.unavailable }
        return descriptor
    }

    public static func prepare(_ request: HanlinNativePresentationRequest,
                               store: HanlinScriptExtensionStore,
                               action: HanlinWidgetActionCommand? = nil) throws -> HanlinNativePresentationExecution {
        _ = try HanlinInstalledPackageID(validating: request.identity.installedPackageID.rawValue)
        _ = try HanlinPackageID(validating: request.identity.packageID.rawValue)
        guard request.identity.generation > 0 else { throw HanlinNativePresentationError.invalidRequest }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let requestBytes = try encoder.encode(request)
        let inputSHA = digest(requestBytes)
        let identitySHA = digest(try encoder.encode(request.identity))
        let stateURL = store.root.appendingPathComponent("Packages", isDirectory: true)
            .appendingPathComponent(request.identity.installedPackageID.rawValue, isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(String(request.identity.generation), isDirectory: true)
            .appendingPathComponent("presentations", isDirectory: true)
            .appendingPathComponent(identitySHA, isDirectory: true)
            .appendingPathComponent(request.sessionID.uuidString + ".json")
        var execution: HanlinNativePresentationExecution?
        try store.update { snapshot in
            guard let snapshot else { throw HanlinNativePresentationError.unavailable }
            let descriptor = try descriptor(for: request, in: snapshot)
            let bytes = try store.loadVerifiedArtifact(ref: descriptor.programRef, sha256: descriptor.programSHA256,
                installedPackageID: request.identity.installedPackageID, generation: request.identity.generation)
            let program = try JSONDecoder().decode(HanlinWidgetProgram.self, from: bytes)
            try program.validate(engine: descriptor.engine)
            var state = State(inputSHA256: inputSHA, artifactSHA256: descriptor.programSHA256,
                revision: 0, values: [:], committedNonces: [])
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let saved = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
                if saved.inputSHA256 == inputSHA && saved.artifactSHA256 == descriptor.programSHA256 { state = saved }
            }

            var environment: [String: HanlinValue] = [
                "widgetFamily": .string("systemLarge"), "family": .string("systemLarge"),
                "timestamp": .number(Date.now.timeIntervalSince1970 * 1_000)
            ]
            environment["presentation"] = try HanlinWidgetJSON.value([
                "kind": request.kind.rawValue, "sessionID": request.sessionID.uuidString,
                "inputText": request.inputText, "parameters": request.parameters.toAny(),
                "allowsReplacement": request.allowsReplacement
            ])
            let resources = try store.materializeResources(program.resources, identity: request.identity)
            let context = HanlinWidgetActionContext(identity: request.identity, engine: descriptor.engine,
                artifactSHA256: descriptor.programSHA256, family: "systemLarge", environment: environment,
                actions: program.actions, resources: resources, presentation: request)
            var declaration: HanlinWidgetActionDeclaration?
            var replay = false
            if let action {
                guard action.context.identity == request.identity, action.context.presentation == request,
                      action.context.engine == descriptor.engine,
                      action.context.artifactSHA256 == descriptor.programSHA256 else {
                    throw HanlinNativePresentationError.staleProgram
                }
                guard let declared = program.actions.first(where: { $0.id == action.actionID }) else {
                    throw HanlinNativePresentationError.invalidAction
                }
                declaration = declared
                replay = !action.nonce.isEmpty && state.committedNonces.contains(action.nonce)
            }

            let prepared: HanlinPreparedWidget
            var effect = HanlinNativePresentationEffect()
            switch descriptor.engine {
            case .expo:
                if let action, let declaration, declaration.kind != .reload, !replay {
                    guard declaration.kind == .expoCallback, action.target == declaration.id else {
                        throw HanlinNativePresentationError.invalidAction
                    }
                    environment["target"] = .string(action.target)
                    let result = try HanlinExpoWidgetsRuntime.shared.handlePress(layout: program.javaScript,
                        props: state.values.mapValues { $0.toAny() },
                        environment: environment.mapValues { $0.toAny() }).get()
                    guard let result else { throw HanlinWidgetActionError.noCallback }
                    state.values.merge(try HanlinWidgetJSON.dictionary(result)) { _, new in new }
                }
                // These reserved values are produced by the typed native
                // presentation helpers in Expo layouts and consumed once.
                if let raw = state.values.removeValue(forKey: "__hanlinPresentationEffect") {
                    effect = try JSONDecoder().decode(HanlinNativePresentationEffect.self, from: raw.jsonValue().canonicalJSONData())
                }
                let node = try HanlinExpoWidgetsRuntime.shared.render(layout: program.javaScript,
                    props: state.values.mapValues { $0.toAny() },
                    environment: environment.mapValues { $0.toAny() }).get()
                prepared = .expo(node: try HanlinWidgetJSON.value(node), context: context)
            case .scriptwidget:
                if let declaration, declaration.kind == .setValue, !replay {
                    guard let key = declaration.stateKey, let desired = action?.desiredValue else {
                        throw HanlinWidgetActionError.missingValue
                    }
                    state.values[key] = .bool(desired)
                }
                let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: state.values,
                    environment: environment,
                    actionID: !replay && declaration?.handler != nil ? declaration?.id : nil,
                    actionValue: action?.desiredValue, actionParameters: action?.parameters ?? .null,
                    nativeRoot: store.root.appendingPathComponent("ScriptWidgetOriginal/v1", isDirectory: true),
                    nativeIdentity: try HanlinScriptWidgetRuntime.nativeIdentity(request.identity,
                        artifactSHA256: descriptor.programSHA256) + ":" + request.sessionID.uuidString)
                state.values = result.values
                effect = result.presentationEffect
                prepared = .scriptwidget(node: result.node, context: context)
            case .legacy: throw HanlinNativePresentationError.unavailable
            }
            guard state.revision < UInt64.max else { throw HanlinNativePresentationError.invalidState }
            state.revision += 1
            if let action, !action.nonce.isEmpty, !replay {
                state.committedNonces = Array((state.committedNonces + [action.nonce]).suffix(128))
            }
            let encodedState = try encoder.encode(state)
            guard encodedState.count <= HanlinScriptExtensionStore.maximumArtifactBytes else {
                throw HanlinNativePresentationError.invalidState
            }
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encodedState.write(to: stateURL, options: .atomic)
            execution = .init(prepared: prepared, effect: effect, revision: state.revision)
            return snapshot
        }
        guard let execution else { throw HanlinNativePresentationError.invalidState }
        return execution
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
