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

        // Assistant tool call preservation check across ALL assistant messages
        if let expectedAssistantCalls = expectation.expectedAssistantToolCalls {
            var allCalls: [(messageIndex: Int, callIndex: Int, id: String, name: String, arguments: String)] = []
            var seenCallIDs = Set<String>()

            for (msgIdx, msg) in messages.enumerated() {
                guard (msg["role"] as? String) == "assistant",
                      let calls = msg["tool_calls"] as? [[String: Any]] else {
                    continue
                }
                for (callIdx, callDict) in calls.enumerated() {
                    guard let id = callDict["id"] as? String else { continue }
                    if seenCallIDs.contains(id) {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Duplicate assistant tool call ID '\(id)' found in message history at message \(msgIdx)."
                        )
                    }
                    seenCallIDs.insert(id)
                    let fn = callDict["function"] as? [String: Any]
                    let name = fn?["name"] as? String ?? ""
                    let args = fn?["arguments"] as? String ?? ""
                    allCalls.append((msgIdx, callIdx, id, name, args))
                }
            }

            for exp in expectedAssistantCalls {
                let matches = allCalls.filter { $0.id == exp.id }
                if matches.isEmpty {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Assistant tool_calls missing expected call ID '\(exp.id)' across complete message history."
                    )
                }
                if matches.count > 1 {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Duplicate assistant tool call ID '\(exp.id)' found in message history."
                    )
                }
                let match = matches[0]
                if match.name != exp.name {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Assistant tool call '\(exp.id)' expected name '\(exp.name)', got '\(match.name)'."
                    )
                }
                if let argValidator = exp.argumentsValidator,
                   !argValidator(match.arguments) {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Assistant tool call '\(exp.id)' arguments failed validation: \(match.arguments)."
                    )
                }
            }
        }

        // Tool result message check (MUST be role=tool, MUST have matching tool_call_id)
        if let expectedResults = expectation.expectedToolResults {
            var toolMessages: [(messageIndex: Int, callID: String, content: Any?)] = []
            var seenResultIDs = Set<String>()

            for (msgIdx, msg) in messages.enumerated() {
                guard (msg["role"] as? String) == "tool" else { continue }
                guard let callID = msg["tool_call_id"] as? String else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Tool message at index \(msgIdx) missing 'tool_call_id'."
                    )
                }
                if seenResultIDs.contains(callID) {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Duplicate tool result for tool_call_id '\(callID)' at message \(msgIdx)."
                    )
                }
                seenResultIDs.insert(callID)
                let content = msg["content"]
                toolMessages.append((msgIdx, callID, content))
            }

            for exp in expectedResults {
                let matches = toolMessages.filter { $0.callID == exp.callID }
                if matches.isEmpty {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Missing tool result message with role='tool' and tool_call_id='\(exp.callID)'."
                    )
                }
                if matches.count > 1 {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Duplicate tool result message with tool_call_id='\(exp.callID)'."
                    )
                }
                let match = matches[0]

                if let expectedContent = exp.expectedContent {
                    switch expectedContent {
                    case .present:
                        guard match.content != nil else {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Tool result for '\(exp.callID)' missing 'content' key."
                            )
                        }
                    case .exact(let exactStr):
                        guard let str = match.content as? String else {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Tool result for '\(exp.callID)' content is not a String (expected exact \"\(exactStr)\"). Observed: \(String(describing: match.content))."
                            )
                        }
                        if str != exactStr {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Tool result for '\(exp.callID)' content expected exact \"\(exactStr)\", observed \"\(str)\"."
                            )
                        }
                    case .contains(let sub):
                        let str = (match.content as? String) ?? ""
                        if !str.contains(sub) {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Tool result for '\(exp.callID)' did not contain expected '\(sub)'. Observed: \(str)."
                            )
                        }
                    }
                }
            }

            // Chronology validation: assistant(call X) must occur before tool(result X)
            for exp in expectedResults {
                guard let toolMsg = toolMessages.first(where: { $0.callID == exp.callID }) else { continue }
                if let asstMsg = messages.firstIndex(where: { msg in
                    guard (msg["role"] as? String) == "assistant",
                          let calls = msg["tool_calls"] as? [[String: Any]] else { return false }
                    return calls.contains(where: { ($0["id"] as? String) == exp.callID })
                }) {
                    if asstMsg >= toolMsg.messageIndex {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Chronology violation: assistant tool call '\(exp.callID)' (message \(asstMsg)) must occur before tool result (message \(toolMsg.messageIndex))."
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
        // Preserved thinking/signature check
        if expectation.expectedThoughtSignature != nil || expectation.expectedPreservedReasoning != nil {
            let assistantMsgs = messages.filter { ($0["role"] as? String) == "assistant" }
            var foundThinkingBlocks: [[String: Any]] = []
            for msg in assistantMsgs {
                if let contentBlocks = msg["content"] as? [[String: Any]] {
                    foundThinkingBlocks.append(contentsOf: contentBlocks.filter { ($0["type"] as? String) == "thinking" })
                }
            }

            if let expectedSig = expectation.expectedThoughtSignature {
                guard foundThinkingBlocks.contains(where: { ($0["signature"] as? String) == expectedSig }) else {
                    let sigs = foundThinkingBlocks.compactMap { $0["signature"] as? String }
                    throw ConformanceProtocolError(
                        category: .SIGNATURE_STATE,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Anthropic assistant missing thinking block with signature '\(expectedSig)'. Observed signatures: \(sigs)."
                    )
                }
            }

            if let expectedReasoning = expectation.expectedPreservedReasoning {
                guard foundThinkingBlocks.contains(where: {
                    let text = ($0["thinking"] as? String) ?? ""
                    return text.contains(expectedReasoning)
                }) else {
                    throw ConformanceProtocolError(
                        category: .REASONING_STATE,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Anthropic assistant thinking block missing expected text '\(expectedReasoning)'."
                    )
                }
            }
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
            let userMsgs = messages.enumerated().filter { ($0.element["role"] as? String) == "user" }
            var foundResultBlocks: [(userMsgIndex: Int, blockIndex: Int, toolUseID: String, content: Any?, isError: Bool?)] = []
            var seenResultIDs = Set<String>()

            for userMsg in userMsgs {
                if let contentBlocks = userMsg.element["content"] as? [[String: Any]] {
                    for (bIdx, block) in contentBlocks.enumerated() {
                        if (block["type"] as? String) == "tool_result",
                           let toolUseID = block["tool_use_id"] as? String {
                            if seenResultIDs.contains(toolUseID) {
                                throw ConformanceProtocolError(
                                    category: .TOOL_RESULT_CONTINUATION,
                                    ownership: .swiftAISDKDependency,
                                    round: round,
                                    message: "Duplicate Anthropic tool_result block for tool_use_id '\(toolUseID)'."
                                )
                            }
                            seenResultIDs.insert(toolUseID)
                            let isErr = block["is_error"] as? Bool
                            foundResultBlocks.append((userMsg.offset, bIdx, toolUseID, block["content"], isErr))
                        }
                    }
                }
            }

            for exp in expectedResults {
                guard let match = foundResultBlocks.first(where: { $0.toolUseID == exp.callID }) else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Anthropic user content missing tool_result block with tool_use_id '\(exp.callID)'."
                    )
                }

                if let expectedContent = exp.expectedContent {
                    switch expectedContent {
                    case .present:
                        guard match.content != nil else {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Anthropic tool_result for '\(exp.callID)' missing content key."
                            )
                        }
                    case .exact(let exactStr):
                        guard let str = match.content as? String else {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Anthropic tool_result for '\(exp.callID)' content is not a String (expected exact \"\(exactStr)\"). Observed: \(String(describing: match.content))."
                            )
                        }
                        if str != exactStr {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Anthropic tool_result for '\(exp.callID)' content expected exact \"\(exactStr)\", observed \"\(str)\"."
                            )
                        }
                    case .contains(let sub):
                        let str = (match.content as? String) ?? ""
                        if !str.contains(sub) {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Anthropic tool_result for '\(exp.callID)' did not contain expected '\(sub)'. Observed: \(str)."
                            )
                        }
                    }
                }

                if exp.isError {
                    if match.isError != true {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Anthropic tool_result for '\(exp.callID)' expected is_error=true, got \(String(describing: match.isError))."
                        )
                    }
                }
            }

            // Chronology: assistant message containing tool_use must occur before user message containing tool_result
            for exp in expectedResults {
                guard let resultBlock = foundResultBlocks.first(where: { $0.toolUseID == exp.callID }) else { continue }
                if let asstIdx = messages.firstIndex(where: { msg in
                    guard (msg["role"] as? String) == "assistant",
                          let contentBlocks = msg["content"] as? [[String: Any]] else { return false }
                    return contentBlocks.contains(where: { ($0["type"] as? String) == "tool_use" && ($0["id"] as? String) == exp.callID })
                }) {
                    if asstIdx >= resultBlock.userMsgIndex {
                        throw ConformanceProtocolError(
                            category: .TOOL_RESULT_CONTINUATION,
                            ownership: .swiftAISDKDependency,
                            round: round,
                            message: "Chronology violation: Anthropic tool_use '\(exp.callID)' at message \(asstIdx) must precede tool_result at message \(resultBlock.userMsgIndex)."
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
            struct ParsedGoogleResponse {
                let name: String
                let id: String?
                let responseDict: [String: Any]?
                let responseRaw: Any?
            }

            var functionResponses: [ParsedGoogleResponse] = []
            for msg in contents {
                if let parts = msg["parts"] as? [[String: Any]] {
                    for p in parts {
                        if let fr = p["functionResponse"] as? [String: Any] {
                            let name = fr["name"] as? String ?? ""
                            let respDict = fr["response"] as? [String: Any]
                            let id = (fr["id"] as? String) ?? (respDict?["id"] as? String)
                            functionResponses.append(ParsedGoogleResponse(
                                name: name,
                                id: id,
                                responseDict: respDict,
                                responseRaw: fr["response"]
                            ))
                        }
                    }
                }
            }

            var matchedIndices = Set<Int>()

            for exp in expectedResults {
                var foundIndex: Int?
                for (idx, resp) in functionResponses.enumerated() {
                    guard !matchedIndices.contains(idx) else { continue }
                    if let respID = resp.id, !respID.isEmpty, respID == exp.callID {
                        foundIndex = idx
                        break
                    }
                }
                if foundIndex == nil {
                    for (idx, resp) in functionResponses.enumerated() {
                        guard !matchedIndices.contains(idx) else { continue }
                        if resp.name == (exp.name ?? exp.callID) {
                            foundIndex = idx
                            break
                        }
                    }
                }

                guard let matchIdx = foundIndex else {
                    throw ConformanceProtocolError(
                        category: .TOOL_RESULT_CONTINUATION,
                        ownership: .swiftAISDKDependency,
                        round: round,
                        message: "Google content missing functionResponse for '\(exp.callID)' (name: \(exp.name ?? "nil"))."
                    )
                }

                matchedIndices.insert(matchIdx)
                let match = functionResponses[matchIdx]

                if let expectedContent = exp.expectedContent {
                    let contentStr = match.responseDict != nil ? String(describing: match.responseDict!) : String(describing: match.responseRaw ?? "")
                    switch expectedContent {
                    case .present:
                        guard match.responseRaw != nil else {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Google functionResponse for '\(exp.callID)' missing response content."
                            )
                        }
                    case .exact(let exactStr):
                        let str = (match.responseDict?["output"] as? String)
                            ?? (match.responseDict?["result"] as? String)
                            ?? (match.responseDict?["content"] as? String)
                            ?? (match.responseRaw as? String)
                            ?? contentStr
                        if str != exactStr {
                            throw ConformanceProtocolError(
                                category: .TOOL_RESULT_CONTINUATION,
                                ownership: .swiftAISDKDependency,
                                round: round,
                                message: "Google functionResponse for '\(exp.callID)' expected exact \"\(exactStr)\", observed \"\(str)\"."
                            )
                        }
                    case .contains(let sub):
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

    // MARK: - Harness Direct Regression Check (Section 3)

    public static func validateMultiAssistantToolCallRegression() throws {
        let json: [String: Any] = [
            "messages": [
                [
                    "role": "assistant",
                    "tool_calls": [
                        ["id": "call-1", "type": "function", "function": ["name": "tool_1", "arguments": "{}"]]
                    ]
                ],
                [
                    "role": "tool",
                    "tool_call_id": "call-1",
                    "content": "result-1"
                ],
                [
                    "role": "assistant",
                    "tool_calls": [
                        ["id": "call-2", "type": "function", "function": ["name": "tool_2", "arguments": "{}"]]
                    ]
                ],
                [
                    "role": "tool",
                    "tool_call_id": "call-2",
                    "content": "result-2"
                ],
                [
                    "role": "assistant",
                    "tool_calls": [
                        ["id": "call-3", "type": "function", "function": ["name": "tool_3", "arguments": "{}"]]
                    ]
                ]
            ]
        ]

        let expectation = RoundExpectation(
            expectedAssistantToolCalls: [
                ExpectedToolCall(id: "call-2", name: "tool_2"),
                ExpectedToolCall(id: "call-3", name: "tool_3")
            ],
            expectedToolResults: [
                ExpectedToolResult(callID: "call-1", expectedContent: .exact("result-1")),
                ExpectedToolResult(callID: "call-2", expectedContent: .exact("result-2"))
            ]
        )

        try validateOpenAINative(json: json, round: 2, expectation: expectation)
    }
}
