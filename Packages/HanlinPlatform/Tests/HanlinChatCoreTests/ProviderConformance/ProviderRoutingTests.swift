import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
@testable import HanlinChatCore
import Testing

@Suite("Provider Routing & Inventory Conformance Tests")
struct ProviderRoutingTests {

    // MARK: - Core Provider Descriptors

    @Test("OpenAI native routing for api.openai.com")
    func testOpenAINativeRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            displayName: "GPT-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "sk-test"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAI)
        #expect(desc.modelID == "gpt-4o")
        #expect(desc.baseURL.absoluteString == "https://api.openai.com/v1")
        #expect(desc.headers.isEmpty)
    }

    @Test("OpenAI-Response routing characterization (Section 6 mandatory test)")
    func testOpenAIResponseRoutingCharacterization() {
        // Characterization finding:
        // APIType "openAIResponse" / "openai-response" pointing to api.openai.com
        // currently routes through the OpenAI Chat completions provider because
        // HanlinAISDKProviderFactory resolves company == "OPENAI" to .openAI,
        // and normalizeBaseURL trims /responses.
        // It does NOT yet route to a dedicated Responses API adapter.
        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            displayName: "GPT-4o",
            company: "OpenAI",
            apiType: "openAIResponse",
            endpoint: "https://api.openai.com/v1/responses",
            credential: "sk-test"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAI, "Characterization finding: openAIResponse routes to .openAI chatModel rather than dedicated Responses adapter.")
        #expect(desc.baseURL.absoluteString == "https://api.openai.com/v1")
    }

    @Test("OpenAI with custom host routes to openAICompatible")
    func testOpenAICustomHostRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "custom-gpt",
            displayName: "Custom GPT",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://my-proxy.company.internal/v1/chat/completions",
            credential: "sk-custom"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAICompatible)
        #expect(desc.baseURL.absoluteString == "https://my-proxy.company.internal/v1")
    }

    @Test("OpenRouter profile sets HTTP-Referer, X-Title, and openAICompatible kind")
    func testOpenRouterRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "nvidia/llama-3.1-nemotron-70b-instruct",
            displayName: "Nemotron",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            credential: "sk-or-v1-test"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAICompatible)
        #expect(desc.modelID == "nvidia/llama-3.1-nemotron-70b-instruct")
        #expect(desc.baseURL.absoluteString == "https://openrouter.ai/api/v1")
        #expect(desc.headers["HTTP-Referer"] == "https://hanlin.ai")
        #expect(desc.headers["X-Title"] == "Hanlin")
    }

    @Test("Google Generative AI routing and endpoint normalization")
    func testGoogleRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "gemini-2.0-flash-exp",
            displayName: "Gemini Flash",
            company: "Google",
            apiType: "gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            credential: "AIzaSyTest"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .google)
        #expect(desc.modelID == "gemini-2.0-flash-exp")
        #expect(desc.baseURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta")
    }

    @Test("Gemini company name routes to native google provider")
    func testGeminiCompanyNameRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "gemini-1.5-pro",
            displayName: "Gemini 1.5 Pro",
            company: "Gemini",
            apiType: "gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/chat/completions",
            credential: "AIzaSyTest2"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .google)
    }

    @Test("Anthropic routing and endpoint normalization")
    func testAnthropicRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "claude-3-5-sonnet-20241022",
            displayName: "Claude 3.5 Sonnet",
            company: "Anthropic",
            apiType: "anthropic",
            endpoint: "https://api.anthropic.com/v1/messages",
            credential: "sk-ant-test"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .anthropic)
        #expect(desc.baseURL.absoluteString == "https://api.anthropic.com/v1")
    }

    @Test("LAN and local host routing to openAICompatible")
    func testLANRouting() {
        let config = HanlinChatModelConfiguration(
            modelID: "qwen2.5:7b",
            displayName: "Local Qwen",
            company: "LAN",
            apiType: "openai",
            endpoint: "http://192.168.1.100:11434/v1/chat/completions",
            credential: "LOCAL_DUMMY"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAICompatible)
        #expect(desc.baseURL.absoluteString == "http://192.168.1.100:11434/v1")
    }

    @Test("Custom third-party providers route to openAICompatible")
    func testRepresentativeThirdPartyProviders() {
        let thirdPartyCompanies = [
            ("DeepSeek", "https://api.deepseek.com/v1/chat/completions", "deepseek-chat"),
            ("Qwen", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen-max"),
            ("ZhipuAI", "https://open.bigmodel.cn/api/paas/v4/chat/completions", "glm-4"),
            ("xAI", "https://api.x.ai/v1/chat/completions", "grok-beta"),
            ("Groq", "https://api.groq.com/openai/v1/chat/completions", "llama-3.1-70b-versatile")
        ]

        for (company, endpoint, model) in thirdPartyCompanies {
            let config = HanlinChatModelConfiguration(
                modelID: model,
                company: company,
                apiType: "openai",
                endpoint: endpoint,
                credential: "test-key"
            )
            let desc = HanlinAISDKProviderFactory.descriptor(for: config)
            #expect(desc.kind == .openAICompatible, "Expected \(company) to route to openAICompatible.")
        }
    }

    @Test("Query parameters are preserved during endpoint normalization")
    func testQueryParametersPreserved() {
        let config = HanlinChatModelConfiguration(
            modelID: "custom-model",
            company: "Proxy",
            apiType: "openai",
            endpoint: "https://myproxy.org/v1/chat/completions?team=ai&version=2",
            credential: "test"
        )
        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.queryParameters["team"] == "ai")
        #expect(desc.queryParameters["version"] == "2")
    }

    // MARK: - Inventory Gate (Section 6)

    @Test("All configured provider companies map to known conformance profiles")
    func testAllConfiguredCompaniesResolveToKnownConformanceProfiles() {
        let knownCompanies = [
            "OPENAI",
            "OPENROUTER",
            "GOOGLE",
            "GEMINI",
            "ANTHROPIC",
            "DEEPSEEK",
            "QWEN",
            "ZHIPUAI",
            "XAI",
            "GROQ",
            "OLLAMA",
            "LAN",
            "CUSTOM"
        ]

        var resolvedMatrix: [String: HanlinAISDKProviderKind] = [:]
        for company in knownCompanies {
            let config = HanlinChatModelConfiguration(
                modelID: "test-model",
                company: company,
                apiType: company == "ANTHROPIC" ? "anthropic" : (company == "GOOGLE" || company == "GEMINI" ? "gemini" : "openai"),
                endpoint: "https://api.example.com/v1/chat/completions",
                credential: "key"
            )
            let desc = HanlinAISDKProviderFactory.descriptor(for: config)
            resolvedMatrix[company] = desc.kind
            #expect(desc.kind == .openAI || desc.kind == .openAICompatible || desc.kind == .anthropic || desc.kind == .google)
        }

        #expect(resolvedMatrix["ANTHROPIC"] == .anthropic)
        #expect(resolvedMatrix["GOOGLE"] == .google)
        #expect(resolvedMatrix["GEMINI"] == .google)
        #expect(resolvedMatrix["OPENROUTER"] == .openAICompatible)
    }
}
