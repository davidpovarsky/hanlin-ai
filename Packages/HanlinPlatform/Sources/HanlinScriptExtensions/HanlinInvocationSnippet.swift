import AppIntents
import Foundation
import HanlinPlatformContracts
import SwiftUI

/// A native system snippet reads the durable invocation receipt. Re-evaluation
/// never runs the package action again or infers success from queue admission.
public struct HanlinInvocationSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "MiniApp Action Result"

    @Parameter(title: "Invocation") public var invocationID: String

    public init() { invocationID = "" }
    public init(invocationID: UUID) { self.invocationID = invocationID.uuidString }

    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let id = UUID(uuidString: invocationID) else {
            throw HanlinInvocationSnippetError.invalidInvocation
        }
        let receipt = try HanlinScriptExtensionStore().receipt(for: id)
        return .result(view: HanlinInvocationReceiptView(invocationID: id, receipt: receipt))
    }
}

public struct HanlinRefreshInvocationSnippetIntent: AppIntent {
    public static let title: LocalizedStringResource = "Refresh MiniApp Result"

    @Parameter(title: "Invocation") public var invocationID: String

    public init() { invocationID = "" }
    public init(invocationID: UUID) { self.invocationID = invocationID.uuidString }

    public func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        guard let id = UUID(uuidString: invocationID) else {
            throw HanlinInvocationSnippetError.invalidInvocation
        }
        return .result(snippetIntent: HanlinInvocationSnippetIntent(invocationID: id))
    }
}

private enum HanlinInvocationSnippetError: Error {
    case invalidInvocation
}

private struct HanlinInvocationReceiptView: View {
    let invocationID: UUID
    let receipt: HanlinInvocationReceipt?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            if let receipt {
                if receipt.status == .succeeded, let value = receipt.value {
                    Text(resultText(value))
                        .textSelection(.enabled)
                } else if let failure = receipt.failure {
                    Text(failureText(failure))
                        .foregroundStyle(.secondary)
                }
                Text(receipt.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This action receipt is no longer available in this app.")
                    .foregroundStyle(.secondary)
            }
            if receipt?.status == .queued || receipt?.status == .running {
                Button(intent: HanlinRefreshInvocationSnippetIntent(invocationID: invocationID)) {
                    Label("Refresh result", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    private var title: LocalizedStringKey {
        guard let receipt else { return "Action unavailable" }
        switch receipt.status {
        case .queued: return "Waiting to run"
        case .running: return "Running in MiniApps"
        case .succeeded: return "Action completed"
        case .failed: return "Action failed"
        case .cancelled: return "Action cancelled"
        case .stale: return "Package changed"
        case .expired: return "Action expired"
        case .deferred, .needsForeground: return "Continue in the app"
        case .acknowledged: return "Action acknowledged"
        }
    }

    private var symbol: String {
        switch receipt?.status {
        case .succeeded: "checkmark.circle"
        case .queued, .running: "clock"
        case .cancelled: "xmark.circle"
        case .deferred, .needsForeground: "arrow.up.forward.app"
        default: "exclamationmark.triangle"
        }
    }

    private func resultText(_ value: HanlinValue) -> String {
        if case .string(let text) = value { return text }
        if case .object(let values) = value, let rawSummary = values["summary"],
           case .string(let summary) = rawSummary {
            return summary
        }
        if case .data(let data) = value {
            return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        }
        guard let json = try? value.jsonValue().canonicalJSONData() else {
            return String(localized: "The action returned a result that is available in the app.")
        }
        return String(decoding: json, as: UTF8.self)
    }

    private func failureText(_ failure: HanlinInvocationReceipt.Failure) -> LocalizedStringKey {
        switch failure {
        case .invalidTarget, .staleGeneration, .disabledPackage:
            "The installed package changed. Select its current action again."
        case .unsupportedEntrypoint, .invalidEnvelope:
            "The package does not declare this action or input."
        case .unavailableHost:
            "Open the app to continue this action."
        case .actionFailed:
            "The package reported an error. Open the app for details."
        case .interruptedOutcomeUnknown:
            "The app was interrupted before a result was recorded."
        case .attemptsExhausted:
            "This action could not be completed."
        case .deadlineExceeded:
            "This action expired before it completed."
        }
    }
}

/// Compose this after Run Script Action in Shortcuts. The run action returns its
/// invocation identifier; this action returns only the recorded package result.
public struct HanlinAwaitInvocationResultIntent: AppIntent {
    public static let title: LocalizedStringResource = "Wait for MiniApp Result"
    public static let description = IntentDescription("Waits for an existing MiniApp action and returns its text or JSON result without running it again.")
    public static let openAppWhenRun = true

    @Parameter(title: "Invocation") public var invocationID: String

    public init() { invocationID = "" }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetIntent {
        guard let id = UUID(uuidString: invocationID) else {
            throw HanlinInvocationSnippetError.invalidInvocation
        }
        let store = try HanlinScriptExtensionStore()
        guard let command = try store.command(for: id) else {
            throw HanlinInvocationResultError.missing
        }
        let expiresAt = command.invocation.delivery?.expiresAt
            ?? command.createdAt.addingTimeInterval(86_400)
        while true {
            try Task.checkCancellation()
            guard let receipt = try store.receipt(for: id) else {
                throw HanlinInvocationResultError.missing
            }
            switch receipt.status {
            case .succeeded:
                let value = receipt.value ?? .null
                let result: String
                switch value {
                case .string(let text): result = text
                case .data(let data): result = data.base64EncodedString()
                default: result = String(decoding: try value.jsonValue().canonicalJSONData(), as: UTF8.self)
                }
                return .result(value: result, snippetIntent: HanlinInvocationSnippetIntent(invocationID: id))
            case .queued, .running:
                guard expiresAt > .now else { throw HanlinInvocationResultError.finished(.expired) }
                try await Task.sleep(for: .milliseconds(100))
            default:
                throw HanlinInvocationResultError.finished(receipt.status)
            }
        }
    }
}

private enum HanlinInvocationResultError: LocalizedError {
    case missing
    case finished(HanlinInvocationReceipt.Status)

    var errorDescription: String? {
        switch self {
        case .missing: "This MiniApp invocation could not be found in this app."
        case .finished(let status): "The MiniApp action did not complete successfully (\(status.rawValue))."
        }
    }
}
