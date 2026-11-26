import AppIntents
import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinWidgetUI
import UniformTypeIdentifiers

/// This execution surface belongs to the independent MiniApps application.
/// Hanlin AI continues to consume the shared authoring contracts and old intents.
struct HanlinRunMiniAppShortcutIntent: LongRunningIntent, CancellableIntent {
    static let title: LocalizedStringResource = "Run MiniApp Action"
    static let description = IntentDescription("Runs a saved MiniApp action and returns its actual text, JSON or file result.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Action")
    var action: HanlinScriptActionEntity

    @Parameter(title: "Input Type", default: .text)
    var inputType: MiniAppsShortcutInputType

    @Parameter(title: "Input", default: "")
    var input: String

    @Parameter(title: "JSON File", supportedContentTypes: [.json])
    var jsonFile: IntentFile?

    @Parameter(title: "Allow Long Running", default: false)
    var allowLongRunning: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) with \(\.$input)") {
            \.$inputType
            \.$jsonFile
            \.$allowLongRunning
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ShowsSnippetIntent {
        let inputValue: HanlinValue
        switch inputType {
        case .text:
            inputValue = try HanlinShortcutValueCodec.decode(input, as: .text)
        case .json:
            inputValue = try HanlinShortcutValueCodec.decode(input, as: .dictionaryOrList)
        case .jsonFile:
            guard let jsonFile else { throw MiniAppsShortcutError.missingJSONFile }
            guard let text = String(data: jsonFile.data, encoding: .utf8) else {
                throw MiniAppsShortcutError.invalidUTF8
            }
            inputValue = try HanlinShortcutValueCodec.decode(text, as: .dictionaryOrList)
        }

        let store = try await HanlinScriptingPlatform.productExtensionStore()
        let command = try await MiniAppsShortcutExecution.makeCommand(action: action, input: inputValue)
        let invocationID = command.id
        // Persist before asking the OS for extended time, so cancellation during
        // preparation cannot be lost before the action is admitted.
        try store.enqueue(command)
        let reportedProgress = progress
        let operation = {
            try await MiniAppsShortcutExecution.run(command: command, progress: reportedProgress)
        }
        let value: HanlinValue
        do {
            if allowLongRunning {
                value = try await performBackgroundTask(operation: operation) { _ in
                    _ = try? store.requestCancellation(invocationID)
                }
            } else {
                value = try await withIntentCancellationHandler(operation: operation) { _ in
                    _ = try? store.requestCancellation(invocationID)
                }
            }
        } catch {
            // An OS refusal or preparation error must not leave work to execute
            // later. Terminal receipts keep their real outcome unchanged.
            _ = try? store.requestCancellation(invocationID)
            throw error
        }
        let file: IntentFile
        switch value {
        case .data(let data):
            file = IntentFile(data: data, filename: "MiniApp Result", type: .data)
        case .string(let text):
            file = IntentFile(data: Data(text.utf8), filename: "MiniApp Result.txt", type: .plainText)
        default:
            file = IntentFile(data: try HanlinShortcutValueCodec.encodeJSON(value),
                              filename: "MiniApp Result.json", type: .json)
        }
        return .result(value: file, snippetIntent: HanlinInvocationSnippetIntent(invocationID: invocationID))
    }
}

enum MiniAppsShortcutInputType: String, AppEnum {
    case text, json, jsonFile

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "MiniApp Input")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: "Text",
        .json: "Dictionary or List (JSON)",
        .jsonFile: "JSON File"
    ]
}

private enum MiniAppsShortcutError: LocalizedError {
    case missingJSONFile, invalidUTF8, unavailableAction, unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .missingJSONFile: "Choose a JSON file as input."
        case .invalidUTF8: "The JSON file must contain UTF-8 text."
        case .unavailableAction: "This MiniApp action is no longer available. Select it again."
        case .unsupportedOperation: "This operation requires an interactive MiniApp window."
        }
    }
}

@MainActor
private enum MiniAppsShortcutExecution {
    static func makeCommand(action: HanlinScriptActionEntity, input: HanlinValue) async throws -> HanlinScriptResumeCommand {
        let store = try HanlinScriptingPlatform.productExtensionStore()
        guard let record = try store.load()?.intentEntities.first(where: {
            $0.identity == action.identity
                && "\($0.identity.packageID.rawValue)::\($0.identity.entrypointID)::\($0.id)" == action.id
        }) else { throw MiniAppsShortcutError.unavailableAction }
        let appID = try record.appID ?? HanlinAppID(validating: record.identity.packageID.rawValue)
        return HanlinScriptResumeCommand(invocation: .init(
            identity: record.identity,
            entityID: record.id,
            parameters: input,
            continueInForeground: false,
            delivery: .init(appID: appID, source: .shortcuts,
                            expiresAt: .now.addingTimeInterval(HanlinInvocationDelivery.maximumLifetime - 1),
                            userGesturePresent: true, canPresentUI: false)
        ))
    }

    static func run(command: HanlinScriptResumeCommand, progress: Progress) async throws -> HanlinValue {
        try Task.checkCancellation()
        progress.totalUnitCount = 3
        progress.completedUnitCount = 0
        progress.localizedDescription = String(localized: "Running MiniApp action")
        progress.localizedAdditionalDescription = String(localized: "Preparing app storage")
        try await AppRuntimeCore.shared.prepareStorage()
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        progress.completedUnitCount = 1

        let platform = HanlinScriptingPlatform(actionPresentationAllowed: false,
                                               registersForegroundContinuation: false)
        platform.externalMiniAppOperation = { operation, payload in
            try Task.checkCancellation()
            guard operation == "miniapps.shortcutProgress" else {
                throw MiniAppsShortcutError.unsupportedOperation
            }
            let update = try JSONDecoder().decode(HanlinShortcutProgress.self, from: Data(payload.utf8))
            try update.validate()
            progress.totalUnitCount = update.totalUnitCount
            progress.completedUnitCount = update.completedUnitCount
            if let message = update.message { progress.localizedAdditionalDescription = message }
            return #"{"ok":true}"#
        }
        defer {
            platform.dismissActiveApplication()
            platform.externalMiniAppOperation = nil
        }
        progress.localizedAdditionalDescription = String(localized: "Running saved action")
        progress.completedUnitCount = 2
        let value = try await platform.executeShortcutCommand(command)
        progress.completedUnitCount = progress.totalUnitCount
        progress.localizedAdditionalDescription = String(localized: "Action completed")
        return value
    }
}
