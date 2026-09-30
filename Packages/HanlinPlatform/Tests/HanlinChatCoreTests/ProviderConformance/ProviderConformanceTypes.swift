import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
@testable import HanlinChatCore

// MARK: - Provider Conformance Profiles

/// Represents the wire protocol and capability dialect of a provider,
/// decoupled from marketing model names.
public enum ProviderConformanceProfile: String, CaseIterable, Sendable, Codable {
    case openAINativeChat
    case openAICompatiblePlain
    case openAICompatibleReasoningContent
    case openAICompatibleReasoning
    case openRouterReasoningDetails
    case anthropicNative
    case googleNative

    public var isReasoningCapable: Bool {
        switch self {
        case .openAICompatibleReasoningContent,
             .openAICompatibleReasoning,
             .openRouterReasoningDetails,
             .anthropicNative,
             .googleNative:
            return true
        case .openAINativeChat,
             .openAICompatiblePlain:
            return false
        }
    }

    public var providerKind: HanlinAISDKProviderKind {
        switch self {
        case .openAINativeChat:
            return .openAI
        case .openAICompatiblePlain,
             .openAICompatibleReasoningContent,
             .openAICompatibleReasoning,
             .openRouterReasoningDetails:
            return .openAICompatible
        case .anthropicNative:
            return .anthropic
        case .googleNative:
            return .google
        }
    }
}

// MARK: - Failure Classification (Section 18)

public enum ConformanceFailureCategory: String, CaseIterable, Sendable, Codable {
    case ROUTING
    case REQUEST_SERIALIZATION
    case TOOL_SCHEMA
    case TOOL_CALL_PARSE
    case TOOL_RESULT_CONTINUATION
    case REASONING_STATE
    case SIGNATURE_STATE
    case STREAM_PARSER
    case FINISH_REASON
    case EMPTY_RESPONSE
    case RETRY
    case TOOL_EXECUTION
    case DYNAMIC_TOOL_EXPOSURE
    case CANCELLATION
    case RUN_OWNERSHIP
    case DIAGNOSTICS
    case DIRECT_CHAT_PATH
    case SDK_DEPENDENCY
    case TEST_HARNESS
    case MODEL_NONCOMPLIANCE
}

public enum FailureOwnership: String, CaseIterable, Sendable, Codable {
    case hanlinAIProduction = "hanlin-ai production"
    case swiftAISDKDependency = "swift-ai-sdk dependency"
    case testHarness = "test harness"
    case providerModelBehavior = "provider/model behavior"
    case unknown = "unknown"
}

public struct ConformanceFinding: Sendable, Codable {
    public let profile: ProviderConformanceProfile
    public let scenario: String
    public let round: Int
    public let isPass: Bool
    public let category: ConformanceFailureCategory?
    public let ownership: FailureOwnership?
    public let summary: String
    public let expectedContract: String
    public let observedBehavior: String
    public let requiresProductionFix: Bool

    public init(
        profile: ProviderConformanceProfile,
        scenario: String,
        round: Int,
        isPass: Bool,
        category: ConformanceFailureCategory? = nil,
        ownership: FailureOwnership? = nil,
        summary: String = "",
        expectedContract: String = "",
        observedBehavior: String = "",
        requiresProductionFix: Bool = false
    ) {
        self.profile = profile
        self.scenario = scenario
        self.round = round
        self.isPass = isPass
        self.category = category
        self.ownership = ownership
        self.summary = summary
        self.expectedContract = expectedContract
        self.observedBehavior = observedBehavior
        self.requiresProductionFix = requiresProductionFix
    }
}

// MARK: - Protocol Expectations

public struct ExpectedToolCall: Sendable {
    public let id: String
    public let name: String
    public let argumentsValidator: (@Sendable (String) -> Bool)?

    public init(
        id: String,
        name: String,
        argumentsValidator: (@Sendable (String) -> Bool)? = nil
    ) {
        self.id = id
        self.name = name
        self.argumentsValidator = argumentsValidator
    }
}

public enum ExpectedToolResultContent: Sendable, Equatable {
    case present
    case exact(String)
    case contains(String)
}

public struct ExpectedToolResult: Sendable {
    public let callID: String
    public let name: String?
    public let expectedContent: ExpectedToolResultContent?
    public let isError: Bool

    public var expectedSubstring: String? {
        switch expectedContent {
        case .contains(let s), .exact(let s):
            return s
        case .present, .none:
            return nil
        }
    }

    public init(
        callID: String,
        name: String? = nil,
        expectedSubstring: String? = nil,
        expectedContent: ExpectedToolResultContent? = nil,
        isError: Bool = false
    ) {
        self.callID = callID
        self.name = name
        if let expectedContent {
            self.expectedContent = expectedContent
        } else if let expectedSubstring {
            self.expectedContent = .contains(expectedSubstring)
        } else {
            self.expectedContent = nil
        }
        self.isError = isError
    }
}


public struct RoundExpectation: Sendable {
    public var httpMethod: String
    public var urlPathSuffix: String?
    public var requiredHeaders: [String: String]
    public var forbiddenSubstrings: [String]
    public var expectedToolsAdvertised: [String]?
    public var expectedActiveToolAliases: [String]?
    public var expectedAssistantToolCalls: [ExpectedToolCall]?
    public var expectedToolResults: [ExpectedToolResult]?
    public var expectedPreservedReasoning: String?
    public var expectedReasoningDetailsPresent: Bool?
    public var expectedThoughtSignature: String?
    public var customValidator: (@Sendable (URLRequest, Int, ProviderConformanceProfile) throws -> Void)?

    public init(
        httpMethod: String = "POST",
        urlPathSuffix: String? = nil,
        requiredHeaders: [String: String] = [:],
        forbiddenSubstrings: [String] = ["CONFORMANCE_SECRET_DO_NOT_LEAK"],
        expectedToolsAdvertised: [String]? = nil,
        expectedActiveToolAliases: [String]? = nil,
        expectedAssistantToolCalls: [ExpectedToolCall]? = nil,
        expectedToolResults: [ExpectedToolResult]? = nil,
        expectedPreservedReasoning: String? = nil,
        expectedReasoningDetailsPresent: Bool? = nil,
        expectedThoughtSignature: String? = nil,
        customValidator: (@Sendable (URLRequest, Int, ProviderConformanceProfile) throws -> Void)? = nil
    ) {
        self.httpMethod = httpMethod
        self.urlPathSuffix = urlPathSuffix
        self.requiredHeaders = requiredHeaders
        self.forbiddenSubstrings = forbiddenSubstrings
        self.expectedToolsAdvertised = expectedToolsAdvertised
        self.expectedActiveToolAliases = expectedActiveToolAliases
        self.expectedAssistantToolCalls = expectedAssistantToolCalls
        self.expectedToolResults = expectedToolResults
        self.expectedPreservedReasoning = expectedPreservedReasoning
        self.expectedReasoningDetailsPresent = expectedReasoningDetailsPresent
        self.expectedThoughtSignature = expectedThoughtSignature
        self.customValidator = customValidator
    }
}

public enum ExpectedTerminalOutcome: Sendable {
    case completed(expectedFinalSubstring: String?)
    case failed(expectedErrorType: String?)
    case cancelled
}

// MARK: - Tool Execution Ledger (Section 5)

public final class ToolExecutionLedger: @unchecked Sendable {
    public struct Record: Sendable, Codable {
        public let toolName: String
        public let toolCallID: String
        public let arguments: String
        public var startCount: Int
        public var completionCount: Int
        public var resultText: String?
        public var errorText: String?
        public var orderIndex: Int
        public var runID: String
    }

    private var records: [String: Record] = [:]
    private var orderCounter: Int = 0
    private let lock = NSLock()

    public init() {}

    public func recordStart(toolName: String, callID: String, arguments: String, runID: String = "run-1") {
        lock.lock()
        defer { lock.unlock() }
        orderCounter += 1
        if var existing = records[callID] {
            existing.startCount += 1
            records[callID] = existing
        } else {
            records[callID] = Record(
                toolName: toolName,
                toolCallID: callID,
                arguments: arguments,
                startCount: 1,
                completionCount: 0,
                resultText: nil,
                errorText: nil,
                orderIndex: orderCounter,
                runID: runID
            )
        }
    }

    public func recordCompletion(callID: String, resultText: String) {
        lock.lock()
        defer { lock.unlock() }
        if var existing = records[callID] {
            existing.completionCount += 1
            existing.resultText = resultText
            records[callID] = existing
        }
    }

    public func recordError(callID: String, errorText: String) {
        lock.lock()
        defer { lock.unlock() }
        if var existing = records[callID] {
            existing.completionCount += 1
            existing.errorText = errorText
            records[callID] = existing
        }
    }

    public var allRecords: [Record] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records.values).sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    public func record(for callID: String) -> Record? {
        lock.lock()
        defer { lock.unlock() }
        return records[callID]
    }

    public func assertSingleExecutions() throws {
        lock.lock()
        let items = records.values
        lock.unlock()

        for item in items {
            if item.startCount != 1 {
                throw ConformanceProtocolError(
                    category: .TOOL_EXECUTION,
                    ownership: .hanlinAIProduction,
                    round: -1,
                    message: "Tool '\(item.toolName)' (ID: \(item.toolCallID)) startCount was \(item.startCount), expected 1."
                )
            }
            if item.completionCount != 1 {
                throw ConformanceProtocolError(
                    category: .TOOL_EXECUTION,
                    ownership: .hanlinAIProduction,
                    round: -1,
                    message: "Tool '\(item.toolName)' (ID: \(item.toolCallID)) completionCount was \(item.completionCount), expected 1."
                )
            }
        }
    }
}

// MARK: - Conformance Transcript (Section 5)

public final class ConformanceTranscript: @unchecked Sendable {
    public struct RoundEntry: Sendable, Codable {
        public let round: Int
        public let url: String
        public let headers: [String: String]
        public let bodyText: String
        public let responseChunks: [String]
        public let finishReasonRaw: String?
        public let finishReasonNormalized: String?
    }

    public let profile: ProviderConformanceProfile
    public let scenarioName: String
    private var rounds: [RoundEntry] = []
    public var terminalState: String?
    public var errorMessage: String?
    private let lock = NSLock()

    public init(profile: ProviderConformanceProfile, scenarioName: String) {
        self.profile = profile
        self.scenarioName = scenarioName
    }

    public func recordRound(
        round: Int,
        url: String,
        headers: [String: String],
        bodyData: Data,
        responseChunks: [String],
        rawFinish: String?,
        normalizedFinish: String?
    ) {
        lock.lock()
        defer { lock.unlock() }

        // Sanitize headers
        var sanitizedHeaders = headers
        for (k, _) in sanitizedHeaders {
            let lower = k.lowercased()
            if lower == "authorization" || lower == "x-api-key" || lower.contains("key") || lower.contains("token") {
                sanitizedHeaders[k] = "<redacted>"
            }
        }

        // Sanitize body text
        var bodyStr = String(decoding: bodyData, as: UTF8.self)
        if bodyStr.contains("CONFORMANCE_SECRET_DO_NOT_LEAK") {
            bodyStr = bodyStr.replacingOccurrences(of: "CONFORMANCE_SECRET_DO_NOT_LEAK", with: "<redacted-secret>")
        }

        rounds.append(RoundEntry(
            round: round,
            url: url,
            headers: sanitizedHeaders,
            bodyText: bodyStr,
            responseChunks: responseChunks,
            finishReasonRaw: rawFinish,
            finishReasonNormalized: normalizedFinish
        ))
    }

    public var allRounds: [RoundEntry] {
        lock.lock()
        defer { lock.unlock() }
        return rounds
    }

    public func jsonSummary() -> String {
        lock.lock()
        defer { lock.unlock() }
        let dict: [String: Any] = [
            "profile": profile.rawValue,
            "scenario": scenarioName,
            "roundCount": rounds.count,
            "terminalState": terminalState ?? "none",
            "errorMessage": errorMessage ?? "none"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return "{}"
    }
}

// MARK: - Conformance Protocol Error

public struct ConformanceProtocolError: Error, CustomStringConvertible, Sendable {
    public let category: ConformanceFailureCategory
    public let ownership: FailureOwnership
    public let round: Int
    public let message: String

    public var description: String {
        "[\(category.rawValue) / \(ownership.rawValue) / Round \(round)] \(message)"
    }
}
