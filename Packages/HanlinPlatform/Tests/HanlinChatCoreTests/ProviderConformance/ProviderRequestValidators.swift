import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
@testable import HanlinChatCore

public enum ProviderRequestValidators {

    // MARK: - Main Validation Entry Point

    public static func validate(
        request: URLRequest,
        round: Int,
        expectation: RoundExpectation,
        profile: ProviderConformanceProfile
    ) throws {
        // 1. Method
        let method = request.httpMethod ?? "GET"
        if method != expectation.httpMethod {
            throw ConformanceProtocolError(
                category: .REQUEST_SERIALIZATION,
                ownership: .hanlinAIProduction,
                round: round,
                message: "Expected HTTP method \(expectation.httpMethod), observed \(method)."
            )
        }

        // 2. URL Path
        if let suffix = expectation.urlPathSuffix,
           let path = request.url?.path,
           !path.hasSuffix(suffix) {
            throw ConformanceProtocolError(
                category: .ROUTING,
                ownership: .hanlinAIProduction,
                round: round,
                message: "Expected URL path to end with '\(suffix)', observed '\(path)'."
            )
        }

        // 3. Required Headers
        let headers = request.allHTTPHeaderFields ?? [:]
        for (reqKey, reqVal) in expectation.requiredHeaders {
            guard let val = headers[reqKey] ?? headers[reqKey.lowercased()] else {
                throw ConformanceProtocolError(
                    category: .REQUEST_SERIALIZATION,
                    ownership: .hanlinAIProduction,
                    round: round,
                    message: "Missing required header '\(reqKey)'."
                )
            }
            if !reqVal.isEmpty && val != reqVal {
                throw ConformanceProtocolError(
                    category: .REQUEST_SERIALIZATION,
                    ownership: .hanlinAIProduction,
                    round: round,
                    message: "Header '\(reqKey)' expected '\(reqVal)', observed '\(val)'."
                )
            }
        }

        // 4. Forbidden secret leakage
        let bodyData = extractBody(from: request)
        let bodyString = String(decoding: bodyData, as: UTF8.self)
        for forbidden in expectation.forbiddenSubstrings {
            for (hKey, hVal) in headers {
                if hVal.contains(forbidden) {
                    throw ConformanceProtocolError(
                        category: .DIAGNOSTICS,
                        ownership: .hanlinAIProduction,
                        round: round,
                        message: "Forbidden secret leaked in header '\(hKey)'."
                    )
                }
            }
            if bodyString.contains(forbidden) {
                throw ConformanceProtocolError(
                    category: .DIAGNOSTICS,
                    ownership: .hanlinAIProduction,
                    round: round,
                    message: "Forbidden secret leaked in request body."
                )
            }
        }

        // 5. Parse JSON Body
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw ConformanceProtocolError(
                category: .REQUEST_SERIALIZATION,
                ownership: .hanlinAIProduction,
                round: round,
                message: "Request body could not be parsed as JSON dictionary."
            )
        }

        // 6. Provider-specific wire validations
        switch profile {
        case .openAINativeChat:
            try validateOpenAINative(json: json, round: round, expectation: expectation)
        case .openAICompatiblePlain,
             .openAICompatibleReasoningContent,
             .openAICompatibleReasoning,
             .openRouterReasoningDetails:
            try validateOpenAICompatible(json: json, round: round, expectation: expectation, profile: profile, headers: headers)
        case .anthropicNative:
            try validateAnthropicNative(json: json, round: round, expectation: expectation)
        case .googleNative:
            try validateGoogleNative(json: json, round: round, expectation: expectation)
        }

        // 7. Custom Validator callback
        try expectation.customValidator?(request, round, profile)
    }

    // MARK: - Body Extraction

    public static func extractBody(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    // MARK: - OpenAI Native Validator

    private static func validateOpenAINative(
        json: [String: Any],
        round: Int,
        expectation: RoundExpectation
    ) throws {
        guard let messages = json["messages"] as? [[String: Any]] else {
            throw ConformanceProtocolError(
                category: .REQUEST_SERIALIZATION,
                ownership: .swiftAISDKDependency,
                round: round,
                message: "OpenAI request missing 'messages' array."
            )
        }

        // Advertised tools check
        if let expectedTools = expectation.expectedToolsAdvertised {
            let tools = (json["tools"] as? [[String: Any]]) ?? []
            let toolNames = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
            for name in expectedTools {
                if !toolNames.contains(name) {
                    throw ConformanceProtocolError(
                        category: .TOOL_SCHEMA,
                        ownership: .hanlinAIProduction,
                        round: round,
                        message: "Expected advertised tool '\(name)', but found tools: \(toolNames)."
                    )
                }
            }
        }

        // Assistant tool call preservation check
        if let expectedAssistantCalls = expectation.expectedAssistantToolCalls {
            guard let assistantMsg = messages.first(where: { ($0["role"] as? String) == "assistant" && $0["tool_calls"] != nil }) else {
                throw ConformanceProtocolError(
                    category: .TOOL_RESULT_CONTINUATION,
                    ownership: .swiftAISDKDependency,
                    round: round,
                    message: "Expected assistant message with tool_calls in continuation, but none found."
                )
            }
            guard let calls = assistantMsg["tool_calls"] as? [[String: Any]] else {
                throw ConformanceProtocolError(
                    category: .TOOL_RESULT_CONTINUATION,
                    ownership: .swiftAISDKDependency,
                    round: round,
                    message: "Assistant message tool_calls is not an array."
                )
            }
            for exp in expectedAssistantCalls {
                guard let match = calls.first(where: { ($0["id"] as? String) == exp.id }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Assistant tool_calls missing expected call ID '\(exp.id)'."
                    )
                }
                let fn = match["function"] as? [String: Any]
                let fnName = fn?["name"] as? String
                if fnName != exp.name {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Assistant tool call '\(exp.id)' expected name '\(exp.name)', got '\(fnName ?? "nil")'."
                    )
                }
                if let argValidator = exp.argumentsValidator,
                   let argsStr = fn?["arguments"] as? String,
                   !argValidator(argsStr) {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Assistant tool call '\(exp.id)' arguments failed validation: \(argsStr)."
                    )
                }
            }
        }

        // Tool result message check (MUST be role=tool, MUST have matching tool_call_id)
        if let expectedResults = expectation.expectedToolResults {
            let toolMsgs = messages.filter { ($0["role"] as? String) == "tool" }
            for exp in expectedResults {
                guard let match = toolMsgs.first(where: { ($0["tool_call_id"] as? String) == exp.callID }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Missing tool result message with role='tool' and tool_call_id='\(exp.callID)'."
                    )
                }
                if let sub = exp.expectedSubstring {
                    let content = match["content"] as? String ?? ""
                    if !content.contains(sub) {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Tool result for '\(exp.callID)' did not contain expected '\(sub)'. Observed: \(content)."
                        )
                    }
                }
            }
        }
    }

    // MARK: - OpenAI Compatible Validator

    private static func validateOpenAICompatible(
        json: [String: Any],
        round: Int,
        expectation: RoundExpectation,
        profile: ProviderConformanceProfile,
        headers: [String: String]
    ) throws {
        // First run standard OpenAI checks
        try validateOpenAINative(json: json, round: round, expectation: expectation)

        // OpenRouter headers
        if profile == .openRouterReasoningDetails {
            if headers["HTTP-Referer"] == nil && headers["http-referer"] == nil {
                throw ConformanceProtocolError(
                    category: .REQUEST_SERIALIZATION,
                    ownership: .hanlinAIProduction,
                    round: round,
                    message: "OpenRouter profile requires HTTP-Referer header."
                )
            }
            if headers["X-Title"] == nil && headers["x-title"] == nil {
                throw ConformanceProtocolError(
                    category: .REQUEST_SERIALIZATION,
                    ownership: .hanlinAIProduction,
                    round: round,
                    message: "OpenRouter profile requires X-Title header."
                )
            }
        }

        guard let messages = json["messages"] as? [[String: Any]] else { return }

        // Preserved reasoning check
        if let expectedReasoning = expectation.expectedPreservedReasoning {
            let assistantMsg = messages.first { ($0["role"] as? String) == "assistant" }
            let reasoning = (assistantMsg?["reasoning_content"] as? String)
                ?? (assistantMsg?["reasoning"] as? String)
            guard let reasoning, reasoning.contains(expectedReasoning) else {
                throw ConformanceProtocolError(
                    category: .REASONING_STATE,
                    ownership: .swiftAISDKDependency,
                    round: round,
                    message: "Expected assistant message to preserve reasoning containing '\(expectedReasoning)', observed: \(reasoning ?? "nil")."
                )
            }
        }

        // OpenRouter reasoning_details check
        if expectation.expectedReasoningDetailsPresent == true {
            let assistantMsg = messages.first { ($0["role"] as? String) == "assistant" }
            guard assistantMsg?["reasoning_details"] != nil else {
                throw ConformanceProtocolError(
                    category: .REASONING_STATE,
                    ownership: .swiftAISDKDependency,
                    round: round,
                    message: "Missing preserved provider reasoning_details on assistant message."
                )
            }
        }
    }

    // MARK: - Anthropic Native Validator

    private static func validateAnthropicNative(
        json: [String: Any],
        round: Int,
        expectation: RoundExpectation
    ) throws {
        guard let messages = json["messages"] as? [[String: Any]] else {
            throw ConformanceProtocolError(
                category: .REQUEST_SERIALIZATION,
                ownership: .swiftAISDKDependency,
                round: round,
                message: "Anthropic request missing 'messages' array."
            )
        }

        // Reject role=tool in Anthropic!
        if messages.contains(where: { ($0["role"] as? String) == "tool" }) {
            throw ConformanceProtocolError(
                category: .TOOL_RESULT_CONTINUATION,
                ownership: .swiftAISDKDependency,
                round: round,
                message: "Anthropic request serialized role='tool'. Anthropic requires tool_result content blocks in role='user'."
            )
        }

        // Assistant tool_use content blocks
        if let expectedAssistantCalls = expectation.expectedAssistantToolCalls {
            let assistantMsgs = messages.filter { ($0["role"] as? String) == "assistant" }
            var foundToolUseBlocks: [[String: Any]] = []
            for msg in assistantMsgs {
                if let contentBlocks = msg["content"] as? [[String: Any]] {
                    foundToolUseBlocks.append(contentsOf: contentBlocks.filter { ($0["type"] as? String) == "tool_use" })
                }
            }

            for exp in expectedAssistantCalls {
                guard let match = foundToolUseBlocks.first(where: { ($0["id"] as? String) == exp.id }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Anthropic assistant missing tool_use block with id '\(exp.id)'."
                    )
                }
                let name = match["name"] as? String
                if name != exp.name {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Anthropic tool_use '\(exp.id)' expected name '\(exp.name)', got '\(name ?? "nil")'."
                    )
                }
            }
        }

        // User tool_result content blocks
        if let expectedResults = expectation.expectedToolResults {
            let userMsgs = messages.filter { ($0["role"] as? String) == "user" }
            var foundResultBlocks: [[String: Any]] = []
            for msg in userMsgs {
                if let contentBlocks = msg["content"] as? [[String: Any]] {
                    foundResultBlocks.append(contentsOf: contentBlocks.filter { ($0["type"] as? String) == "tool_result" })
                }
            }

            for exp in expectedResults {
                guard let match = foundResultBlocks.first(where: { ($0["tool_use_id"] as? String) == exp.callID }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Anthropic user content missing tool_result block with tool_use_id '\(exp.callID)'."
                    )
                }
                if let sub = exp.expectedSubstring {
                    let content = match["content"] as? String ?? ""
                    if !content.contains(sub) {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Anthropic tool_result for '\(exp.callID)' did not contain expected '\(sub)'. Observed: \(content)."
                        )
                    }
                }
                if exp.isError {
                    let isErrorVal = match["is_error"] as? Bool
                    if isErrorVal != true {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Anthropic tool_result for '\(exp.callID)' expected is_error=true, got \(String(describing: isErrorVal))."
                        )
                    }
                }
            }
        }
    }

    // MARK: - Google Native Validator

    private static func validateGoogleNative(
        json: [String: Any],
        round: Int,
        expectation: RoundExpectation
    ) throws {
        guard let contents = json["contents"] as? [[String: Any]] else {
            throw ConformanceProtocolError(
                category: .REQUEST_SERIALIZATION,
                ownership: .swiftAISDKDependency,
                round: round,
                message: "Google request missing 'contents' array."
            )
        }

        // Function call preservation in model parts
        if let expectedCalls = expectation.expectedAssistantToolCalls {
            let modelMessages = contents.filter { ($0["role"] as? String) == "model" }
            var functionCalls: [[String: Any]] = []
            for msg in modelMessages {
                if let parts = msg["parts"] as? [[String: Any]] {
                    for p in parts {
                        if let fc = p["functionCall"] as? [String: Any] {
                            var combined = fc
                            if let sig = p["thoughtSignature"] as? String {
                                combined["thoughtSignature"] = sig
                            }
                            functionCalls.append(combined)
                        }
                    }
                }
            }

            for exp in expectedCalls {
                guard let match = functionCalls.first(where: { ($0["name"] as? String) == exp.name }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Google model content missing functionCall for '\(exp.name)'."
                    )
                }
                if let expectedSig = expectation.expectedThoughtSignature {
                    let sig = match["thoughtSignature"] as? String
                    if sig != expectedSig {
                        throw ConformanceProtocolError(
                            category: .SIGNATURE_STATE,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Google functionCall for '\(exp.name)' expected thoughtSignature '\(expectedSig)', observed '\(sig ?? "nil")'."
                        )
                    }
                }
            }
        }

        // Function response preservation
        if let expectedResults = expectation.expectedToolResults {
            var functionResponses: [[String: Any]] = []
            for msg in contents {
                if let parts = msg["parts"] as? [[String: Any]] {
                    for p in parts {
                        if let fr = p["functionResponse"] as? [String: Any] {
                            functionResponses.append(fr)
                        }
                    }
                }
            }

            for exp in expectedResults {
                guard let match = functionResponses.first(where: { ($0["name"] as? String) == (exp.name ?? "") || !functionResponses.isEmpty }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Google content missing functionResponse for '\(exp.callID)'."
                    )
                }
                if let sub = exp.expectedSubstring {
                    let respDict = match["response"] as? [String: Any]
                    let contentStr = String(describing: respDict ?? [:])
                    if !contentStr.contains(sub) {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Google functionResponse did not contain '\(sub)'. Observed: \(contentStr)."
                        )
                    }
                }
            }
        }
    }
}
