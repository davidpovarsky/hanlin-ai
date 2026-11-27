import AppIntents
import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinWidgetUI
import UniformTypeIdentifiers

/// This execution surface belongs to the independent MiniApps application.
/// Hanlin AI continues to consume the shared authoring contracts and old intents.
struct HanlinRunMiniAppShortcutIntent: LongRunningIntent, CancellableIntent {
    static let title = LocalizedStringResource("Run MiniApp Action", table: "HanlinAppIntents")
    static let description = IntentDescription(LocalizedStringResource("Runs a saved MiniApp action and returns its actual text, JSON or file result.", table: "HanlinAppIntents"))
    // The OS selects the mode, including its Open When Run preference.
    // Availability of a foreground transition is never treated as a request.
    static var supportedModes: IntentModes { [.background, .foreground(.immediate)] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: LocalizedStringResource("Action", table: "HanlinAppIntents"))
    var action: HanlinScriptActionEntity

    @Parameter(title: LocalizedStringResource("Input Type", table: "HanlinAppIntents"), default: .text)
    var inputType: MiniAppsShortcutInputType

    @Parameter(title: LocalizedStringResource("Input", table: "HanlinAppIntents"), default: "")
    var input: String

    @Parameter(title: LocalizedStringResource("JSON File", table: "HanlinAppIntents"), supportedContentTypes: [.json])
    var jsonFile: IntentFile?

    @Parameter(title: LocalizedStringResource("Allow Long Running", table: "HanlinAppIntents"), default: false)
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

        let runsInForeground = systemContext.currentMode == .foreground
        let store = try await HanlinScriptingPlatform.productExtensionStore()
        let command = try await MiniAppsShortcutExecution.makeCommand(
            action: action, input: inputValue, canPresentUI: runsInForeground)
        let invocationID = command.id
        let reportedProgress = progress
        let preparation = MiniAppsShortcutPreparationFailure()
        let executor = HanlinInvocationExecutor(store: store)
        let value: HanlinValue
        do {
            // One atomic command/lease record precedes OS preparation. The
            // existing executor renews it throughout preparation and execution.
            let receipt = try await executor.execute(command) { ownedCommand in
                let operation = {
                    await preparation.didStart()
                    return try await MiniAppsShortcutExecution.run(
                        command: ownedCommand, store: store, progress: reportedProgress)
                }
                do {
                    if self.allowLongRunning {
                        return try await self.performBackgroundTask(operation: operation) { _ in
                            _ = try? store.requestCancellation(invocationID)
                        }
                    }
                    return try await self.withIntentCancellationHandler(operation: operation) { _ in
                        _ = try? store.requestCancellation(invocationID)
                    }
                } catch {
                    if await preparation.recordIfUnstarted(error) {
                        _ = try? store.requestCancellation(invocationID)
                        // OS refusal happened before package execution. Preserve
                        // the real OS error for the caller and cancel its lease.
                        throw CancellationError()
                    }
                    throw error
                }
            }
            try await preparation.rethrowIfPresent()
            value = try MiniAppsShortcutExecution.result(receipt, for: invocationID)
            if runsInForeground, let receipt {
                await HanlinScriptingPlatform.shared.settleShortcutPresentation(receipt)
            }
        } catch {
            _ = try? store.requestCancellation(invocationID)
            if runsInForeground {
                await HanlinScriptingPlatform.shared.dismissShortcutPresentation(invocationID, executionFinished: true)
            }
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

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("MiniApp Input", table: "HanlinAppIntents"))
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: DisplayRepresentation(title: LocalizedStringResource("Text", table: "HanlinAppIntents")),
        .json: DisplayRepresentation(title: LocalizedStringResource("Dictionary or List (JSON)", table: "HanlinAppIntents")),
        .jsonFile: DisplayRepresentation(title: LocalizedStringResource("JSON File", table: "HanlinAppIntents"))
    ]
}

enum MiniAppsShortcutError: LocalizedError {
    case missingJSONFile, invalidUTF8, unavailableAction, unsupportedOperation

    var errorDescription: String? {
        switch self {
        case .missingJSONFile: String(localized: "Choose a JSON file as input.", table: "HanlinAppIntents")
        case .invalidUTF8: String(localized: "The JSON file must contain UTF-8 text.", table: "HanlinAppIntents")
        case .unavailableAction: String(localized: "This MiniApp action is no longer available. Select it again.", table: "HanlinAppIntents")
        case .unsupportedOperation: String(localized: "This operation requires an interactive MiniApp window.", table: "HanlinAppIntents")
        }
    }
}

@MainActor
enum MiniAppsShortcutExecution {
    static func makeCommand(action: HanlinScriptActionEntity, input: HanlinValue, canPresentUI: Bool = false) async throws -> HanlinScriptResumeCommand {
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
            continueInForeground: canPresentUI,
            delivery: .init(appID: appID, source: .shortcuts,
                            expiresAt: .now.addingTimeInterval(HanlinInvocationDelivery.maximumLifetime - 1),
                            userGesturePresent: true, canPresentUI: canPresentUI)
        ))
    }

    nonisolated static func result(_ receipt: HanlinInvocationReceipt?, for invocationID: UUID) throws -> HanlinValue {
        guard let receipt, receipt.invocationID == invocationID else {
            throw HanlinInvocationQueueError.missingCommand
        }
        if receipt.status == .succeeded { return receipt.value ?? .null }
        if receipt.status == .cancelled { throw CancellationError() }
        throw HanlinInvocationDispatchError(receipt.status, receipt.failure ?? .actionFailed)
    }

    static func run(command: HanlinScriptResumeCommand, store: HanlinScriptExtensionStore,
                    progress: Progress) async throws -> HanlinValue {
        try Task.checkCancellation()
        progress.totalUnitCount = 3
        progress.completedUnitCount = 0
        progress.localizedDescription = String(localized: "Running MiniApp action", table: "HanlinAppIntents")
        progress.localizedAdditionalDescription = String(localized: "Preparing app storage", table: "HanlinAppIntents")
        try await AppRuntimeCore.shared.prepareStorage()
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
        progress.completedUnitCount = 1

        let presentsUI = command.invocation.delivery?.canPresentUI == true
        let platform = HanlinScriptingPlatform(actionPresentationAllowed: presentsUI,
                                               registersForegroundContinuation: false)
        let reporter = try MiniAppsShortcutProgressReporter(progress: progress, commandID: command.id, store: store)
        platform.externalMiniAppOperation = { operation, payload in
            try reporter.receive(operation, payload: payload)
        }
        var ownedByScene = false
        defer {
            reporter.close()
            // A foreground owner releases or retains its platform only after
            // the executor publishes the terminal receipt. Pre-terminal cleanup
            // must not convert successful work into a cancellation request.
            if !ownedByScene { platform.dismissActiveApplication() }
            platform.externalMiniAppOperation = nil
        }
        if presentsUI {
            let captures = HanlinMiniAppCaptureCoordinator.shared
            guard captures.cameraPresentation == nil, !captures.showsInbox else {
                throw HanlinInvocationDispatchError(.needsForeground, .unavailableHost)
            }
            try HanlinScriptingPlatform.shared.admitShortcutPresentation(platform, command: command, store: store)
            ownedByScene = true
        }
        progress.localizedAdditionalDescription = String(localized: "Running saved action", table: "HanlinAppIntents")
        progress.completedUnitCount = 2
        let value = try await platform.executeClaimedShortcutCommand(command)
        progress.completedUnitCount = progress.totalUnitCount
        progress.localizedAdditionalDescription = String(localized: "Action completed", table: "HanlinAppIntents")
        return value
    }
}

/// A provider captures this object once. Closing it rejects late progress instead
/// of directing a previous action's callback to a later intent or visible app.
@MainActor
final class MiniAppsShortcutProgressReporter {
    private var progress: Progress?
    private let commandID: UUID
    private let leaseID: UUID
    private let store: HanlinScriptExtensionStore

    init(progress: Progress, commandID: UUID, store: HanlinScriptExtensionStore) throws {
        guard let receipt = try store.receipt(for: commandID), receipt.status == .running,
              let leaseID = receipt.leaseID, receipt.leaseExpiresAt.map({ $0 > .now }) == true else {
            throw HanlinInvocationQueueError.staleLease
        }
        self.progress = progress; self.commandID = commandID; self.leaseID = leaseID; self.store = store
    }

    func receive(_ operation: String, payload: String) throws -> String {
        try Task.checkCancellation()
        guard operation == "miniapps.shortcutProgress" else { throw MiniAppsShortcutError.unsupportedOperation }
        guard let progress, let receipt = try store.receipt(for: commandID),
              receipt.status == .running, receipt.leaseID == leaseID,
              receipt.leaseExpiresAt.map({ $0 > .now }) == true, !receipt.cancellationRequested else {
            throw CancellationError()
        }
        let update = try JSONDecoder().decode(HanlinShortcutProgress.self, from: Data(payload.utf8))
        try update.validate()
        progress.totalUnitCount = update.totalUnitCount
        progress.completedUnitCount = update.completedUnitCount
        if let message = update.message { progress.localizedAdditionalDescription = message }
        return #"{"ok":true}"#
    }

    func close() { progress = nil }
}

private actor MiniAppsShortcutPreparationFailure {
    private var started = false
    private var error: (any Error)?

    func didStart() { started = true }
    func recordIfUnstarted(_ error: any Error) -> Bool {
        guard !started else { return false }
        self.error = error
        return true
    }
    func rethrowIfPresent() throws {
        if let error { throw error }
    }
}
