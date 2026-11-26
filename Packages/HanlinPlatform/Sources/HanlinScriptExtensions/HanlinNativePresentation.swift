import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public enum HanlinNativePresentationKind: String, Codable, Hashable, Sendable {
    case snippet, translationUI, keyboard, notificationUI
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

/// UIKit supplies this context. Full Access reflects the operating system's
/// keyboard setting; Hanlin does not add a second permission decision.
public struct HanlinKeyboardContext: Codable, Hashable, Sendable {
    public let documentContextBeforeInput: String?
    public let documentContextAfterInput: String?
    public let selectedText: String?
    public let hasFullAccess: Bool

    public init(documentContextBeforeInput: String? = nil, documentContextAfterInput: String? = nil,
                selectedText: String? = nil, hasFullAccess: Bool) {
        self.documentContextBeforeInput = documentContextBeforeInput
        self.documentContextAfterInput = documentContextAfterInput
        self.selectedText = selectedText
        self.hasFullAccess = hasFullAccess
    }
}

/// Commands address the current textDocumentProxy, never a different app's
/// storage. The native controller applies them in the order returned.
public struct HanlinKeyboardEdit: Codable, Hashable, Sendable {
    public enum Operation: String, Codable, Hashable, Sendable {
        case insertText, deleteBackward, adjustTextPosition, nextInputMode
    }
    public let operation: Operation
    public let text: String?
    public let offset: Int?

    public init(operation: Operation, text: String? = nil, offset: Int? = nil) {
        self.operation = operation
        self.text = text
        self.offset = offset
    }

    public func validate() throws {
        switch operation {
        case .insertText:
            guard text != nil, offset == nil else { throw HanlinNativePresentationError.invalidRequest }
        case .adjustTextPosition:
            guard text == nil, offset != nil else { throw HanlinNativePresentationError.invalidRequest }
        case .deleteBackward, .nextInputMode:
            guard text == nil, offset == nil else { throw HanlinNativePresentationError.invalidRequest }
        }
    }
}

public enum HanlinNotificationPresentationAction: String, Codable, Hashable, Sendable {
    case openApp, dismiss
}

/// Each invocation owns its state, including two snippets from the same package.
/// Keyboard document context can change without resetting its local session state.
public struct HanlinNativePresentationRequest: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let kind: HanlinNativePresentationKind
    public let sessionID: UUID
    public let actionName: String?
    public let inputText: String
    public let parameters: HanlinValue
    public let allowsReplacement: Bool
    public let keyboard: HanlinKeyboardContext?

    public init(identity: HanlinScriptExtensionIdentity, kind: HanlinNativePresentationKind,
                sessionID: UUID = UUID(), actionName: String? = nil, inputText: String = "",
                parameters: HanlinValue = .null, allowsReplacement: Bool = false,
                keyboard: HanlinKeyboardContext? = nil) {
        self.identity = identity
        self.kind = kind
        self.sessionID = sessionID
        self.actionName = actionName
        self.inputText = inputText
        self.parameters = parameters
        self.allowsReplacement = allowsReplacement
        self.keyboard = keyboard
    }
}

public struct HanlinNativePresentationEffect: Codable, Hashable, Sendable {
    public var expandsSheet = false
    public var finishRequested = false
    public var replacementText: String?
    public var keyboardEdits: [HanlinKeyboardEdit] = []
    public var notificationAction: HanlinNotificationPresentationAction?
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case expandsSheet, finishRequested, replacementText, keyboardEdits, notificationAction
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        expandsSheet = try values.decodeIfPresent(Bool.self, forKey: .expandsSheet) ?? false
        finishRequested = try values.decodeIfPresent(Bool.self, forKey: .finishRequested) ?? false
        replacementText = try values.decodeIfPresent(String.self, forKey: .replacementText)
        keyboardEdits = try values.decodeIfPresent([HanlinKeyboardEdit].self, forKey: .keyboardEdits) ?? []
        notificationAction = try values.decodeIfPresent(HanlinNotificationPresentationAction.self, forKey: .notificationAction)
    }

    public func validate(for request: HanlinNativePresentationRequest) throws {
        guard keyboardEdits.isEmpty || request.kind == .keyboard,
              notificationAction == nil || request.kind == .notificationUI else {
            throw HanlinNativePresentationError.invalidRequest
        }
        for edit in keyboardEdits { try edit.validate() }
    }
}

/// Extension-local mode reads the shared publication without taking a writable
/// shared lock. All resources, session state and original native service storage
/// are materialized below the extension's own application-support directory.
public enum HanlinNativePresentationStorage: Hashable, Sendable {
    case shared
    case extensionLocal(root: URL)
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

/// Native execution uses immutable installed programs and the original engines.
/// Snippet/translation callers retain the existing shared transaction behavior.
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
        case .keyboard, .notificationUI:
            descriptor = snapshot.nativePresentations.first {
                $0.identity == request.identity && $0.kind == request.kind
            }?.nativePresentation
        }
        guard let descriptor, descriptor.engine != .legacy else { throw HanlinNativePresentationError.unavailable }
        return descriptor
    }

    public static func prepare(_ request: HanlinNativePresentationRequest,
                               store: HanlinScriptExtensionStore,
                               action: HanlinWidgetActionCommand? = nil,
                               storage: HanlinNativePresentationStorage = .shared,
                               executionControl: HanlinScriptWidgetExecutionControl = .init()) throws -> HanlinNativePresentationExecution {
        try executionControl.checkCancellation()
        _ = try HanlinInstalledPackageID(validating: request.identity.installedPackageID.rawValue)
        _ = try HanlinPackageID(validating: request.identity.packageID.rawValue)
        guard request.identity.generation > 0,
              request.kind != .keyboard || request.keyboard != nil else {
            throw HanlinNativePresentationError.invalidRequest
        }
        switch storage {
        case .shared:
            return try store.withLock {
                guard let snapshot = try store.loadUnlocked().snapshot else {
                    throw HanlinNativePresentationError.unavailable
                }
                return try execute(request, catalog: snapshot, catalogStore: store, stateStore: store, action: action, executionControl: executionControl)
            }
        case let .extensionLocal(root):
            let local = HanlinScriptExtensionStore(root: root)
            // An accidental shared-root argument must not silently turn a
            // keyboard's read-only catalog mode into writes to the App Group.
            let catalogPath = store.root.resolvingSymlinksInPath().standardizedFileURL.path
            let localPath = local.root.resolvingSymlinksInPath().standardizedFileURL.path
            guard localPath != catalogPath, !localPath.hasPrefix(catalogPath + "/") else {
                throw HanlinNativePresentationError.invalidRequest
            }
            return try local.withLock {
                guard let snapshot = try store.loadReadOnly() else {
                    throw HanlinNativePresentationError.unavailable
                }
                let before = try descriptor(for: request, in: snapshot)
                let result = try execute(request, catalog: snapshot, catalogStore: store, stateStore: local, action: action, executionControl: executionControl)
                // A host may disable, remove or replace a package while its
                // original runtime is working. Never deliver that stale effect.
                guard let current = try store.loadReadOnly(),
                      try descriptor(for: request, in: current) == before else {
                    throw HanlinNativePresentationError.staleProgram
                }
                return result
            }
        }
    }

    private static func execute(_ request: HanlinNativePresentationRequest,
                                catalog: HanlinScriptExtensionSnapshot,
                                catalogStore: HanlinScriptExtensionStore,
                                stateStore: HanlinScriptExtensionStore,
                                action: HanlinWidgetActionCommand?, executionControl: HanlinScriptWidgetExecutionControl) throws -> HanlinNativePresentationExecution {
        try executionControl.checkCancellation()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Changing keyboard text context updates the render/action input, not
        // the installation's session. Snippet and translation hashing is unchanged.
        let stateRequest = request.kind == .keyboard
            ? HanlinNativePresentationRequest(identity: request.identity, kind: request.kind,
                sessionID: request.sessionID, actionName: request.actionName, parameters: request.parameters)
            : request
        let inputSHA = digest(try encoder.encode(stateRequest))
        let identitySHA = digest(try encoder.encode(request.identity))
        let stateURL = stateStore.root.appendingPathComponent("Packages", isDirectory: true)
            .appendingPathComponent(request.identity.installedPackageID.rawValue, isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(String(request.identity.generation), isDirectory: true)
            .appendingPathComponent("presentations", isDirectory: true)
            .appendingPathComponent(identitySHA, isDirectory: true)
            .appendingPathComponent(request.sessionID.uuidString + ".json")
        let descriptor = try descriptor(for: request, in: catalog)
        let bytes = try catalogStore.loadVerifiedArtifact(ref: descriptor.programRef, sha256: descriptor.programSHA256,
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
        var presentation: [String: Any] = [
            "kind": request.kind.rawValue, "sessionID": request.sessionID.uuidString,
            "inputText": request.inputText, "parameters": request.parameters.toAny(),
            "allowsReplacement": request.allowsReplacement
        ]
        if let keyboard = request.keyboard {
            presentation["keyboard"] = try JSONSerialization.jsonObject(with: encoder.encode(keyboard))
        }
        environment["presentation"] = try HanlinWidgetJSON.value(presentation)
        let resources = try stateStore.materializeResources(program.resources, identity: request.identity)
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
            if let raw = state.values.removeValue(forKey: "__hanlinPresentationEffect") {
                effect = try JSONDecoder().decode(HanlinNativePresentationEffect.self,
                    from: raw.jsonValue().canonicalJSONData(limits: .unbounded))
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
                nativeRoot: stateStore.root.appendingPathComponent("ScriptWidgetOriginal/v1", isDirectory: true),
                nativeIdentity: try HanlinScriptWidgetRuntime.nativeIdentity(request.identity,
                    artifactSHA256: descriptor.programSHA256) + ":" + request.sessionID.uuidString, executionControl: executionControl)
            state.values = result.values
            effect = result.presentationEffect
            prepared = .scriptwidget(node: result.node, context: context)
        case .legacy: throw HanlinNativePresentationError.unavailable
        }
        // Re-rendering a replay may reconstruct controls, but must not repeat
        // a committed document mutation or notification handoff.
        if replay { effect = .init() }
        try effect.validate(for: request)
        guard state.revision < UInt64.max else { throw HanlinNativePresentationError.invalidState }
        state.revision += 1
        if let action, !action.nonce.isEmpty, !replay {
            state.committedNonces = Array((state.committedNonces + [action.nonce]).suffix(128))
        }
        let encodedState = try encoder.encode(state)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try executionControl.checkCancellation()
        try encodedState.write(to: stateURL, options: .atomic)
        return .init(prepared: prepared, effect: effect, revision: state.revision)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
