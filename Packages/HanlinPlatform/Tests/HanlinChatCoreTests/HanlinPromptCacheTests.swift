import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
import Testing
@testable import HanlinChatCore

@Suite("Hanlin prompt cache policy and original provider integration")
struct HanlinPromptCacheTests {
    private let scope = HanlinPromptCacheScope(
        namespace: ["hanlin", "fixture-account", "fixture-workspace", "fixture-space"],
        conversationID: "fixture-conversation", promptVersion: "hanlin-system-v2"
    )

    private func configuration(
        model: String = "claude-sonnet-4-6",
        company: String = "Anthropic",
        apiType: String = "anthropic",
        endpoint: String = "https://api.anthropic.com/v1/messages",
        credential: String = "fixture-credential",
        reasoning: Bool = false,
        systemPrompt: String? = nil,
        policy: HanlinPromptCachePolicy? = nil
    ) -> HanlinChatModelConfiguration {
        HanlinChatModelConfiguration(
            modelID: model, company: company, apiType: apiType, endpoint: endpoint,
            credential: credential, supportsReasoning: reasoning, thinkingLength: 2048,
            supportsToolUse: true, systemPrompt: systemPrompt, promptCachePolicy: policy
        )
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private actor Capture {
        var requests: [URLRequest] = []
        var didDiscover = false
        func append(_ request: URLRequest) -> Int {
            requests.append(request)
            return requests.count
        }
        func markDiscovered() { didDiscover = true }
    }

    private static func sse(_ payloads: [String], url: URL) -> FetchResponse {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for payload in payloads { continuation.yield(Data("data: \(payload)\n\n".utf8)) }
            continuation.finish()
        }
        return FetchResponse(body: .stream(stream), urlResponse: HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]
        )!)
    }

    @Test("Historical snapshots retain automatic policy and unknown cache-write accounting")
    func historicalSnapshotsDecode() throws {
        let encoded = try JSONEncoder().encode(configuration())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "promptCachePolicy")
        let restored = try JSONDecoder().decode(HanlinChatModelConfiguration.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.promptCachePolicy == nil)
        let options = try HanlinAISDKProviderFactory.providerOptions(configuration: restored, kind: .anthropic)
        #expect(options?["anthropic"]?["cacheControl"] == .object(["type": .string("ephemeral"), "ttl": .string("5m")]))

        let historical = try JSONDecoder().decode(HanlinChatTokenUsage.self,
            from: Data(#"{"inputTokens":100,"outputTokens":4,"cachedInputTokens":30,"totalTokens":104}"#.utf8))
        #expect(historical.cacheWriteTokens == nil)
        let reportedZero = HanlinChatTokenUsage(inputTokens: 100, cacheWriteTokens: 0)
        #expect(try JSONDecoder().decode(HanlinChatTokenUsage.self,
            from: JSONEncoder().encode(reportedZero)).cacheWriteTokens == 0)

        let policy = HanlinPromptCachePolicy(openAI: .init(mode: .explicit, ttl: .twelveHours),
            anthropicTTL: .oneHour)
        #expect(try JSONDecoder().decode(HanlinPromptCachePolicy.self,
            from: JSONEncoder().encode(policy)) == policy)
    }

    @Test("Opaque scopes remain stable across credentials and isolate namespaces, models and conversations")
    func scopedKeysAreStableAndPartitioned() {
        let config = configuration()
        let key = scope.key(configuration: config)
        #expect(key.count == 64)
        #expect(!key.contains("fixture"))
        #expect(key == scope.key(configuration: configuration(credential: "rotated-fixture-credential")))
        #expect(key != scope.key(configuration: configuration(model: "claude-opus-4-6")))
        #expect(key != scope.key(configuration: configuration(endpoint: "https://api.anthropic.com/proxy/messages")))
        #expect(key != HanlinPromptCacheScope(namespace: scope.namespace,
            conversationID: "another-conversation", promptVersion: scope.promptVersion).key(configuration: config))
        #expect(key != HanlinPromptCacheScope(namespace: ["hanlin", "another-account"],
            conversationID: scope.conversationID, promptVersion: scope.promptVersion).key(configuration: config))
        let framedA = HanlinPromptCacheScope(namespace: ["ab", "c"], conversationID: "d", promptVersion: "v")
        let framedB = HanlinPromptCacheScope(namespace: ["a", "bc"], conversationID: "d", promptVersion: "v")
        #expect(framedA.key(configuration: config) != framedB.key(configuration: config))
        let queryA = configuration(endpoint: "https://fixture-user:fixture-password@api.anthropic.com/v1/messages?key=first#one")
        let queryB = configuration(endpoint: "https://api.anthropic.com/v1/messages?key=second#two")
        #expect(scope.key(configuration: queryA) == scope.key(configuration: queryB))
        #expect(scope.key(configuration: queryA) == key)
    }

    @Test("Cache policy merges with reasoning and omits unsupported transport controls")
    func providerOptionsPreserveReasoningAndCompatibility() throws {
        let config = configuration(reasoning: true, policy: .init(anthropicTTL: .oneHour))
        let options = try HanlinAISDKProviderFactory.providerOptions(configuration: config, kind: .anthropic)
        #expect(options?["anthropic"]?["thinking"] == .object([
            "type": .string("enabled"), "budgetTokens": .number(2048)
        ]))
        #expect(options?["anthropic"]?["cacheControl"] == .object([
            "type": .string("ephemeral"), "ttl": .string("1h")
        ]))
        for policy in [HanlinPromptCachePolicy.providerDefault, .noExplicitCaching] {
            let optedOut = configuration(policy: policy)
            #expect(try HanlinAISDKProviderFactory.cacheProviderOptions(configuration: optedOut,
                kind: .anthropic, cacheScope: scope, validateExplicitReference: true).isEmpty)
            #expect(HanlinAISDKProviderFactory.cacheBreakpointOptions(configuration: optedOut, kind: .anthropic) == nil)
        }
        let excludedKinds: [HanlinAISDKProviderKind] = [.openAICompatible, .appleOnDevice]
        for kind in excludedKinds {
            #expect(try HanlinAISDKProviderFactory.cacheProviderOptions(configuration: config,
                kind: kind, cacheScope: scope, validateExplicitReference: true).isEmpty)
        }
        let plan = configuration(model: "gpt-6.2-sol", company: "OpenAI", apiType: "openai-chatgpt-plan",
            endpoint: "https://chatgpt.com/backend-api/codex/responses",
            policy: .init(openAI: .init(mode: .explicit, ttl: .twelveHours)))
        let planOptions = try HanlinAISDKProviderFactory.providerOptions(configuration: plan,
            kind: .openAIResponses, cacheScope: scope, validateExplicitReference: true)
        #expect(planOptions == ["openai": ["store": .bool(false)]])
        #expect(HanlinAISDKProviderFactory.cacheBreakpointOptions(configuration: plan, kind: .openAIResponses) == nil)
    }

    @Test("Legacy and compact Anthropic requests keep stable and changing instructions in distinct blocks")
    func legacyAnthropicWireKeepsStablePrefix() throws {
        let config = configuration(systemPrompt: "Stable instructions", policy: .init(anthropicTTL: .oneHour))
        let request = try HanlinChatRequestBuilder.buildRequest(messages: [.user("Question")],
            configuration: config, systemContext: "Today and memory", cacheScope: scope)
        let json = try body(request)
        let system = try #require(json["system"] as? [[String: Any]])
        #expect(system.count == 2)
        #expect(system[0]["text"] as? String == "Stable instructions")
        #expect(system[1]["text"] as? String == "Context:\nToday and memory")
        #expect((system[0]["cache_control"] as? [String: String]) == ["type": "ephemeral", "ttl": "1h"])
        #expect(system[1]["cache_control"] == nil)
        #expect((json["cache_control"] as? [String: String]) == ["type": "ephemeral", "ttl": "1h"])

        let optedOut = try HanlinChatRequestBuilder.buildRequest(formattedMessages: [
            ["role": "system", "content": "Stable"], ["role": "user", "content": "Question"]
        ], configuration: configuration(policy: .noExplicitCaching))
        #expect(try body(optedOut)["cache_control"] == nil)
        #expect(try body(optedOut)["system"] as? String == "Stable")
    }

    @Test("OpenAI legacy wire uses only supported cache options and an opaque scope")
    func openAIWireUsesTypedPolicy() throws {
        let policy = HanlinPromptCachePolicy(openAI: .init(mode: .implicit, ttl: .thirtyMinutes, retention: .inMemory))
        let config = configuration(model: "gpt-5.6", company: "OpenAI", apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions", policy: policy)
        let request = try HanlinChatRequestBuilder.buildRequest(formattedMessages: [
            ["role": "developer", "content": "Stable"], ["role": "user", "content": "Question"]
        ], configuration: config, cacheScope: scope)
        let json = try body(request)
        #expect(json["prompt_cache_key"] as? String == scope.key(configuration: config))
        #expect(json["prompt_cache_retention"] as? String == "in_memory")
        #expect((json["prompt_cache_options"] as? [String: String]) == ["mode": "implicit", "ttl": "30m"])
        let messages = try #require(json["messages"] as? [[String: Any]])
        let parts = try #require(messages.first?["content"] as? [[String: Any]])
        #expect((parts.first?["prompt_cache_breakpoint"] as? [String: String]) == ["mode": "explicit", "ttl": "30m"])

        let unsupported = configuration(model: "gpt-6.2-sol", company: "OpenAI", apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            policy: .init(openAI: .init(ttl: .twelveHours)))
        #expect(throws: (any Error).self) {
            try HanlinChatRequestBuilder.buildRequest(formattedMessages: [["role": "user", "content": "Question"]],
                configuration: unsupported, cacheScope: scope)
        }
        let compatible = configuration(model: "custom", company: "Custom", apiType: "openai",
            endpoint: "https://models.example.test/v1/chat/completions", policy: policy)
        let compatibleBody = try body(HanlinChatRequestBuilder.buildRequest(
            formattedMessages: [["role": "system", "content": "Stable"], ["role": "user", "content": "Question"]],
            configuration: compatible, cacheScope: scope))
        #expect(compatibleBody["prompt_cache_key"] == nil)
        #expect(compatibleBody["prompt_cache_options"] == nil)
        #expect((compatibleBody["messages"] as? [[String: Any]])?.first?["content"] as? String == "Stable")
        let anthropicCompatible = configuration(apiType: "openai", endpoint: "https://proxy.example.test/v1/chat/completions")
        let proxyBody = try body(HanlinChatRequestBuilder.buildRequest(
            formattedMessages: [["role": "user", "content": "Question"]], configuration: anthropicCompatible))
        #expect(proxyBody["cache_control"] == nil)
    }

    @Test("Anthropic incremental usage normalizes input once, retains cache fields and resets between messages")
    func anthropicUsageSnapshots() throws {
        let parser = HanlinChatStreamParser(apiType: "anthropic")
        let initial = try #require(parser.parse(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":50,"output_tokens":1}}}"#)?.tokenUsage)
        #expect(initial.inputTokens == 100)
        #expect(initial.totalTokens == 101)
        let firstDelta = try #require(parser.parse(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":4}}"#)?.tokenUsage)
        #expect(firstDelta.inputTokens == 100)
        #expect(firstDelta.cachedInputTokens == 30)
        #expect(firstDelta.cacheWriteTokens == 50)
        #expect(firstDelta.outputTokens == 4)
        #expect(firstDelta.totalTokens == 104)
        let secondDelta = try #require(parser.parse(line: #"data: {"type":"message_delta","usage":{"output_tokens":5}}"#)?.tokenUsage)
        #expect(secondDelta.outputTokens == 5)
        #expect(secondDelta.totalTokens == 105)
        let nextMessage = try #require(parser.parse(line: #"data: {"type":"message_start","message":{"usage":{"input_tokens":7,"output_tokens":0}}}"#)?.tokenUsage)
        #expect(nextMessage.inputTokens == 7)
        #expect(nextMessage.cachedInputTokens == nil)
        #expect(nextMessage.cacheWriteTokens == nil)
    }

    @Test("OpenAI and Gemini parser accounting retains read/write and reasoning distinctions")
    func otherProviderUsageSnapshots() throws {
        let openAI = try #require(HanlinChatStreamParser().parse(line:
            #"data: {"usage":{"prompt_tokens":100,"completion_tokens":12,"total_tokens":112,"prompt_tokens_details":{"cached_tokens":30,"cache_write_tokens":50},"completion_tokens_details":{"reasoning_tokens":4}},"choices":[]}"#)?.tokenUsage)
        #expect(openAI.inputTokens == 100)
        #expect(openAI.cacheWriteTokens == 50)
        #expect(openAI.cachedInputTokens == 30)
        #expect(openAI.reasoningTokens == 4)
        let google = try #require(HanlinChatStreamParser(apiType: "gemini").parse(line:
            #"data: {"usageMetadata":{"promptTokenCount":100,"cachedContentTokenCount":80,"candidatesTokenCount":8,"thoughtsTokenCount":4,"totalTokenCount":112},"candidates":[]}"#)?.tokenUsage)
        #expect(google.inputTokens == 100)
        #expect(google.outputTokens == 12)
        #expect(google.reasoningTokens == 4)
        #expect(google.cachedInputTokens == 80)
        #expect(google.cacheWriteTokens == nil)
    }

    @Test("Original Anthropic SDK receives stable breakpoint and retains native read/write usage")
    func originalSDKPreservesSystemBlocksAndCacheUsage() async throws {
        let capture = Capture()
        let fetch: FetchFunction = { request in
            _ = await capture.append(request)
            return Self.sse([
                #"{"type":"message_start","message":{"id":"fixture-message","type":"message","role":"assistant","model":"claude-sonnet-4-6","content":[],"usage":{"input_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":50,"output_tokens":1}}}"#,
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
                #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Answer"}}"#,
                #"{"type":"content_block_stop","index":0}"#,
                #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":4}}"#,
                #"{"type":"message_stop"}"#
            ], url: request.url!)
        }
        let engine = try HanlinAISDKAgentEngine(configuration: configuration(), fetch: fetch)
        let events = try await engine.stream(messages: [
            .init(role: .system, text: "Stable instructions", cacheBreakpoint: true),
            .init(role: .system, text: "Changing date and memory"),
            .init(role: .user, text: "Question")
        ], baseSystemPrompt: nil, tools: [], cacheScope: scope,
            prepareStep: { (_: Int) async in .init(activeToolAliases: [], loadedSkillInstructions: ["Active skill"]) })
        var usage: HanlinChatTokenUsage?
        var text = ""
        for try await event in events {
            if case .textDelta(let delta) = event { text += delta }
            if case .finished(_, let finalUsage) = event { usage = finalUsage }
        }
        #expect(text == "Answer")
        #expect(usage?.inputTokens == 100)
        #expect(usage?.cachedInputTokens == 30)
        #expect(usage?.cacheWriteTokens == 50)
        #expect(usage?.outputTokens == 4)
        let requests = await capture.requests
        #expect(requests.count == 1)
        let json = try body(#require(requests.first))
        let system = try #require(json["system"] as? [[String: Any]])
        #expect(system.map { $0["text"] as? String } == [
            "Stable instructions", "Changing date and memory", "### Active Skill Instructions\nActive skill"
        ])
        #expect((system[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect(system[1]["cache_control"] == nil)
        #expect(system[2]["cache_control"] == nil)
        #expect((json["cache_control"] as? [String: String])?["ttl"] == "5m")
    }

    @Test("Tool catalog continuation keeps usage from every original SDK round")
    func continuationRetainsAllCacheUsage() async throws {
        let capture = Capture()
        let fetch: FetchFunction = { request in
            let index = await capture.append(request)
            let payload = index == 1
                ? #"{"id":"first","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call-discover","type":"function","function":{"name":"discover","arguments":"{}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":100,"completion_tokens":4,"total_tokens":104,"prompt_tokens_details":{"cached_tokens":30,"cache_write_tokens":50}}}"#
                : #"{"id":"second","choices":[{"index":0,"delta":{"content":"Done"},"finish_reason":"stop"}],"usage":{"prompt_tokens":200,"completion_tokens":8,"total_tokens":208,"prompt_tokens_details":{"cached_tokens":100,"cache_write_tokens":60}}}"#
            return Self.sse([payload, "[DONE]"], url: request.url!)
        }
        let config = configuration(model: "gpt-4o", company: "OpenAI", apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions")
        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: fetch)
        let schema = Data(#"{"type":"object","properties":{}}"#.utf8)
        let discover = HanlinAISDKToolDefinition(name: "discover", description: "Discover", inputSchemaData: schema) { _, _ in
            await capture.markDiscovered()
            return .init(modelText: "New tool is available")
        }
        let added = HanlinAISDKToolDefinition(name: "added", description: "Added", inputSchemaData: schema) { _, _ in
            .init(modelText: "Unused")
        }
        let events = try await engine.stream(messages: [.init(role: .user, text: "Discover")],
            baseSystemPrompt: "Stable", tools: [discover],
            dynamicTools: { await capture.didDiscover ? [discover, added] : [discover] },
            cacheScope: scope,
            prepareStep: { (_: Int) async in
                .init(activeToolAliases: await capture.didDiscover ? ["discover", "added"] : ["discover"])
            })
        var usage: HanlinChatTokenUsage?
        for try await event in events {
            if case .finished(_, let finalUsage) = event { usage = finalUsage }
        }
        #expect(await capture.requests.count == 2)
        #expect(usage?.inputTokens == 300)
        #expect(usage?.outputTokens == 12)
        #expect(usage?.cachedInputTokens == 130)
        #expect(usage?.cacheWriteTokens == 110)
        #expect(usage?.totalTokens == 312)
    }

    @Test("Explicit Google references require correct scope and cannot discard system or tools")
    func googleReferenceWireAndConflictChecks() throws {
        let base = configuration(model: "gemini-2.5-flash", company: "Google", apiType: "gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta")
        let reference = HanlinGoogleCachedContentReference(name: "cachedContents/fixture", modelID: base.baseModelID,
            expiresAt: Date().addingTimeInterval(3600), scopeKey: scope.key(configuration: base))
        let config = configuration(model: base.modelID, company: "Google", apiType: "gemini",
            endpoint: base.endpoint.absoluteString, policy: .init(googleCachedContent: reference))
        let request = try HanlinChatRequestBuilder.buildRequest(
            formattedMessages: [["role": "user", "content": "Question"]], configuration: config, cacheScope: scope)
        #expect(try body(request)["cachedContent"] as? String == reference.name)
        #expect(throws: (any Error).self) {
            try HanlinChatRequestBuilder.buildRequest(formattedMessages: [
                ["role": "system", "content": "Must remain"], ["role": "user", "content": "Question"]
            ], configuration: config, cacheScope: scope)
        }
        #expect(throws: (any Error).self) {
            try HanlinChatRequestBuilder.buildRequest(formattedMessages: [["role": "user", "content": "Question"]],
                configuration: config, tools: [["type": "function", "function": [
                    "name": "read", "parameters": ["type": "object"]
                ]]], cacheScope: scope)
        }
        #expect(throws: (any Error).self) {
            try HanlinChatRequestBuilder.buildRequest(formattedMessages: [["role": "user", "content": "Question"]],
                configuration: config, cacheScope: .init(namespace: ["other"], conversationID: "other", promptVersion: "v"))
        }
        #expect(throws: (any Error).self) {
            try HanlinChatRequestBuilder.buildRequest(formattedMessages: [["role": "user", "content": "Question"]],
                configuration: config)
        }
    }
}
