import AppIntents
import CryptoKit
import Foundation
import HanlinExpoWidgetNative
import HanlinPlatformContracts
import HanlinScriptExtensions
import SwiftUI

/// The same native renderer is used in a system snippet and the translation
/// extension. It consumes prepared values; SwiftUI never evaluates JavaScript.
public struct HanlinNativePresentationView: View {
    public let prepared: HanlinPreparedWidget
    public let actionBuilder: (HanlinWidgetActionCommand, SwiftUI.ButtonRole?, AnyView) -> AnyView

    public init(prepared: HanlinPreparedWidget,
                actionBuilder: @escaping (HanlinWidgetActionCommand, SwiftUI.ButtonRole?, AnyView) -> AnyView) {
        self.prepared = prepared
        self.actionBuilder = actionBuilder
    }

    @ViewBuilder public var body: some View {
        switch prepared {
        case let .scriptwidget(node, context):
            HanlinScriptWidgetElementView(node: node, context: context) { command, label in
                actionBuilder(command, nil, label)
            }
        case let .expo(node, context):
            if let object = node.toAny() as? [String: Any] {
                let child = HanlinExpoWidgetNative.render(node: object, resources: context.resources) { target, role, label in
                    guard context.actions.contains(where: { $0.id == target && $0.kind == .expoCallback }) else {
                        return AnyView(label.disabled(true))
                    }
                    return actionBuilder(.init(context: context, actionID: target, nonce: UUID().uuidString), role, label)
                }
                AnyView(child)
            } else {
                Text("The native presentation returned an invalid view.")
            }
        case let .failure(message):
            ContentUnavailableView("MiniApp", systemImage: "exclamationmark.triangle", description: Text(message))
        case .legacy:
            Text("This presentation requires an active native renderer.")
        }
    }
}

public struct HanlinNativePresentationContentView: View {
    public let request: HanlinNativePresentationRequest
    public let store: HanlinScriptExtensionStore
    public let storage: HanlinNativePresentationStorage
    public let onEffect: (HanlinNativePresentationEffect) -> Void
    @State private var prepared: HanlinPreparedWidget?
    @State private var isLoading = false
    @State private var executingRequest: HanlinNativePresentationRequest?
    @State private var executionID: UUID?
    @State private var error: String?

    public init(request: HanlinNativePresentationRequest, store: HanlinScriptExtensionStore,
                storage: HanlinNativePresentationStorage = .shared,
                onEffect: @escaping (HanlinNativePresentationEffect) -> Void = { _ in }) {
        self.request = request
        self.store = store
        self.storage = storage
        self.onEffect = onEffect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                ProgressView().accessibilityIdentifier("hanlin.nativePresentation.loading")
            }
            if let error {
                Text(error).foregroundStyle(.red)
                    .accessibilityIdentifier("hanlin.nativePresentation.error")
                Button("Try again") { Task { await execute() } }
                    .disabled(isLoading)
            }
            if let prepared {
                HanlinNativePresentationView(prepared: prepared) { command, role, label in
                    if let desired = command.desiredValue {
                        return AnyView(Toggle(isOn: Binding(get: { !desired }, set: { value in
                            var update = command
                            update.desiredValue = value
                            Task { await execute(update) }
                        })) { label }
                        .disabled(isLoading)
                        .accessibilityIdentifier("hanlin.nativePresentation.action." + command.actionID))
                    }
                    return AnyView(Button(role: role) {
                        Task { await execute(command) }
                    } label: { label }
                    .disabled(isLoading)
                    .accessibilityIdentifier("hanlin.nativePresentation.action." + command.actionID))
                }
                .accessibilityIdentifier("hanlin.nativePresentation.content")
            }
        }
        .task(id: request) { await execute() }
    }

    @MainActor private func execute(_ command: HanlinWidgetActionCommand? = nil) async {
        let currentRequest = request
        // A new .task(id:) must replace an in-flight older request. Blocking it
        // on a shared loading flag otherwise drops the user's new input.
        guard !isLoading || executingRequest != currentRequest else { return }
        let currentExecution = UUID()
        executionID = currentExecution
        executingRequest = currentRequest
        isLoading = true
        error = nil
        if command == nil { prepared = nil }
        defer {
            if executionID == currentExecution {
                executionID = nil
                executingRequest = nil
                isLoading = false
            }
        }
        let currentStore = store
        let currentStorage = storage
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try HanlinNativePresentationExecutor.prepare(currentRequest, store: currentStore, action: command, storage: currentStorage)
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            guard executionID == currentExecution else { return }
            prepared = result.prepared
            onEffect(result.effect)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, executionID == currentExecution else { return }
            self.error = error.localizedDescription
        }
    }
}

public struct HanlinNativeSnippetEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "MiniApp snippet")
    public static let defaultQuery = HanlinNativeSnippetEntityQuery()
    public let id: String
    public let displayName: String
    public let identity: HanlinScriptExtensionIdentity
    public let actionName: String
    public var displayRepresentation: DisplayRepresentation { .init(title: "\(displayName)") }

    public init(record: HanlinScriptIntentEntityRecord) {
        identity = record.identity
        actionName = record.id
        displayName = record.displayName
        let key = [identity.installedPackageID.rawValue, identity.packageID.rawValue,
                   String(identity.generation), identity.entrypointID, identity.variantID, actionName]
        let encoded = (try? JSONEncoder().encode(key)) ?? Data()
        id = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }
}

public struct HanlinNativeSnippetEntityQuery: EnumerableEntityQuery, EntityStringQuery {
    public init() {}

    public func allEntities() async throws -> [HanlinNativeSnippetEntity] {
        guard let snapshot = try HanlinScriptExtensionStore().load() else { return [] }
        return snapshot.intentEntities.filter {
            $0.nativePresentation != nil &&
                !snapshot.inactiveWidgetInstallations.contains($0.identity.installedPackageID.rawValue)
        }.map(HanlinNativeSnippetEntity.init)
    }

    public func suggestedEntities() async throws -> [HanlinNativeSnippetEntity] { try await allEntities() }
    public func entities(for identifiers: [String]) async throws -> [HanlinNativeSnippetEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }
    public func entities(matching string: String) async throws -> [HanlinNativeSnippetEntity] {
        try await allEntities().filter { string.isEmpty || $0.displayName.localizedCaseInsensitiveContains(string) }
    }
}

/// Direct system entrypoint: executes the installed native presentation without
/// launching the foreground application or turning queue admission into success.
public struct HanlinShowMiniAppSnippetIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show MiniApp Snippet"
    public static let description = IntentDescription("Runs a native presentation supplied by an installed MiniApp and shows its interactive result in Shortcuts.")
    public static let openAppWhenRun = false

    @Parameter(title: "MiniApp") public var miniApp: HanlinNativeSnippetEntity
    @Parameter(title: "Text", default: "") public var text: String
    @Parameter(title: "Parameters JSON", default: "{}") public var parametersJSON: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetIntent {
        let json = try HanlinJSONValue.decodeCanonicalJSON(Data(parametersJSON.utf8), limits: .unbounded)
        let parameters = try HanlinValue(jsonValue: json)
        let request = HanlinNativePresentationRequest(identity: miniApp.identity, kind: .snippet,
            actionName: miniApp.actionName, inputText: text, parameters: parameters)
        guard let snapshot = try HanlinScriptExtensionStore().load() else { throw HanlinNativePresentationError.unavailable }
        _ = try HanlinNativePresentationExecutor.descriptor(for: request, in: snapshot)
        return .result(value: request.sessionID.uuidString, snippetIntent: try HanlinNativePresentationSnippetIntent(request: request))
    }
}

public struct HanlinNativePresentationSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "MiniApp Native Result"
    @Parameter(title: "Native presentation") public var requestJSON: String
    public init() { requestJSON = "{}" }
    public init(request: HanlinNativePresentationRequest) throws {
        requestJSON = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
    }

    @MainActor public func perform() async throws -> some IntentResult & ShowsSnippetView {
        let request = try JSONDecoder().decode(HanlinNativePresentationRequest.self, from: Data(requestJSON.utf8))
        let result = try await Task.detached(priority: .userInitiated) {
            try HanlinNativePresentationExecutor.prepare(request, store: .init())
        }.value
        return .result(view: ScrollView {
            HanlinNativePresentationView(prepared: result.prepared) { command, role, label in
                if let desired = command.desiredValue,
                   let intent = try? HanlinNativePresentationToggleIntent(command: command, value: desired) {
                    return AnyView(Toggle(isOn: !desired, intent: intent) { label }
                        .accessibilityIdentifier("hanlin.nativePresentation.action." + command.actionID))
                }
                if command.desiredValue == nil,
                   let intent = try? HanlinNativePresentationActionIntent(command: command) {
                    return AnyView(Button(role: role, intent: intent) { label }
                        .accessibilityIdentifier("hanlin.nativePresentation.action." + command.actionID))
                }
                return AnyView(label.disabled(true))
            }
            .padding()
            .accessibilityIdentifier("hanlin.nativePresentation.snippet")
        })
    }
}

public struct HanlinNativePresentationActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Update MiniApp Snippet"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    @Parameter(title: "Native action") public var commandJSON: String
    public init() { commandJSON = "{}" }
    public init(command: HanlinWidgetActionCommand) throws {
        commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
    }

    public func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        let command = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(commandJSON.utf8))
        guard let request = command.context.presentation, request.kind == .snippet else {
            throw HanlinNativePresentationError.invalidRequest
        }
        _ = try HanlinNativePresentationExecutor.prepare(request, store: .init(), action: command)
        return .result(snippetIntent: try HanlinNativePresentationSnippetIntent(request: request))
    }
}

/// System toggles provide their intended Boolean through SetValueIntent. The
/// same declared native action executes, then the same snippet renders anew.
public struct HanlinNativePresentationToggleIntent: SetValueIntent {
    public static let title: LocalizedStringResource = "Set MiniApp Snippet Value"
    public static let isDiscoverable = false
    public static let openAppWhenRun = false
    @Parameter(title: "Native action") public var commandJSON: String
    @Parameter(title: "Value") public var value: Bool
    public init() { commandJSON = "{}"; value = false }
    public init(command: HanlinWidgetActionCommand, value: Bool) throws {
        commandJSON = String(decoding: try JSONEncoder().encode(command), as: UTF8.self)
        self.value = value
    }

    public func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        var command = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(commandJSON.utf8))
        guard let request = command.context.presentation, request.kind == .snippet else {
            throw HanlinNativePresentationError.invalidRequest
        }
        command.desiredValue = value
        _ = try HanlinNativePresentationExecutor.prepare(request, store: .init(), action: command)
        return .result(snippetIntent: try HanlinNativePresentationSnippetIntent(request: request))
    }
}

public struct HanlinNativePresentationIntentsPackage: AppIntentsPackage {}
