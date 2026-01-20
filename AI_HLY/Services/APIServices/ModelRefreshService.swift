//
//  ModelRefreshService.swift
//  AI_HLY
//
//  Created by Claude on 2025/1/17.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - 模型结构定义
struct APIModelResponse: Codable {
    let id: String
    let object: String?
    let created: Int?
    let owned_by: String?
}

struct ModelCapabilities {
    var supportsTextGen: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var supportReasoningChange: Bool
    var supportsImageGen: Bool
    var supportsVoiceGen: Bool
    var supportsToolUse: Bool
}

enum ModelCapabilityProbeStep: String, CaseIterable, Identifiable {
    case textGen
    case vision
    case reasoning
    case reasoningControl
    case toolUse
    case imageGen
    case voiceGen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textGen:
            return "文本生成"
        case .vision:
            return "视觉理解"
        case .reasoning:
            return "深度思考"
        case .reasoningControl:
            return "思考模式可控"
        case .toolUse:
            return "工具使用"
        case .imageGen:
            return "图像生成"
        case .voiceGen:
            return "语音生成"
        }
    }
}

enum ModelCapabilityProbeStatus {
    case pending
    case running
    case success
    case failure
}

struct ModelCapabilityProbeSummary {
    let capabilities: ModelCapabilities
}

enum ModelCapabilityProbeError: LocalizedError {
    case invalidAPIKey
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "无效的 API Key"
        case .invalidURL:
            return "无效的请求地址"
        case .invalidResponse:
            return "响应解析失败"
        case .httpError(let statusCode):
            return "HTTP 错误: \(statusCode)"
        }
    }
}

enum ModelCapabilityProbeFailure: Error {
    case failed(step: ModelCapabilityProbeStep, message: String)
}

enum ModelCapabilityProbeResult {
    case success
    case failure(String)
}

/// 带响应数据的探测结果
enum ModelCapabilityProbeResultWithData {
    case success(data: Data)
    case failure(String)
}

enum ModelProbeImageFormat {
    case data
    case dataUrl
}

struct OpenAIModelsResponse: Codable {
    let data: [APIModelResponse]
    let object: String?
}

struct AnthropicModelsResponse: Codable {
    let models: [APIModelResponse]
}

// MARK: - 模型刷新服务
class ModelRefreshService {

    // MARK: 获取模型列表
    static func fetchModelsFromAPI(apiKey: APIKeys) async throws -> [APIModelResponse] {
        guard let key = apiKey.key, !key.isEmpty else {
            throw ModelFetchError.invalidAPIKey
        }

        guard let company = apiKey.company?.uppercased() else {
            throw ModelFetchError.invalidCompany
        }

        // 根据不同的 API 类型调用不同的方法
        switch apiKey.apiType {
        case .openAI, .openAIResponse:
            return try await fetchOpenAIModels(apiKey: apiKey, company: company)
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: apiKey, company: company)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey, company: company)
        }
    }

    // MARK: OpenAI 兼容接口
    private static func fetchOpenAIModels(apiKey: APIKeys, company: String) async throws -> [APIModelResponse] {
        // 构建请求 URL
        let baseURL: String
        if let customURL = apiKey.requestURL, !customURL.isEmpty {
            // 移除末尾的 /chat/completions 如果存在
            let url = customURL.replacingOccurrences(of: "/chat/completions", with: "")
                              .replacingOccurrences(of: "/v1", with: "")
            baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        } else {
            // 使用默认的 URL 配置
            baseURL = getDefaultBaseURL(for: company)
        }

        guard !baseURL.isEmpty else {
            throw ModelFetchError.invalidURL
        }

        let modelsURL = "\(baseURL)/v1/models"
        guard let url = URL(string: modelsURL) else {
            throw ModelFetchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey.key ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let modelsResponse = try decoder.decode(OpenAIModelsResponse.self, from: data)
        return modelsResponse.data
    }

    // MARK: Anthropic 接口
    private static func fetchAnthropicModels(apiKey: APIKeys, company: String) async throws -> [APIModelResponse] {
        let baseURL = apiKey.requestURL ?? "https://api.anthropic.com"
        let modelsURL = "\(baseURL)/v1/models"

        guard let url = URL(string: modelsURL) else {
            throw ModelFetchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey.key ?? "", forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let modelsResponse = try decoder.decode(AnthropicModelsResponse.self, from: data)
        return modelsResponse.models
    }

    // MARK: Gemini 接口
    private static func fetchGeminiModels(apiKey: APIKeys, company: String) async throws -> [APIModelResponse] {
        let baseURL = "https://generativelanguage.googleapis.com"
        let modelsURL = "\(baseURL)/v1beta/models?key=\(apiKey.key ?? "")"

        guard let url = URL(string: modelsURL) else {
            throw ModelFetchError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ModelFetchError.httpError(statusCode: httpResponse.statusCode)
        }

        // Gemini 返回格式略有不同，这里简化处理
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []

        return models.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let modelId = name.replacingOccurrences(of: "models/", with: "")
            return APIModelResponse(id: modelId, object: "model", created: nil, owned_by: "google")
        }
    }

    // MARK: 获取默认 Base URL
    private static func getDefaultBaseURL(for company: String) -> String {
        switch company {
        case "OPENAI":
            return "https://api.openai.com"
        case "DEEPSEEK":
            return "https://api.deepseek.com"
        case "SILICONCLOUD":
            return "https://api.siliconflow.cn"
        case "CHERRY_IN":
            return "https://api.cherrystudio.ai"
        case "N1N":
            return "https://api.n1n.ai"
        case "QWEN":
            return "https://dashscope.aliyuncs.com"
        case "ZHIPUAI":
            return "https://open.bigmodel.cn"
        case "DOUBAO":
            return "https://ark.cn-beijing.volces.com"
        default:
            return ""
        }
    }

    // MARK: - 能力探测
    static func probeModelCapabilities(
        modelId: String,
        company: String,
        context: ModelContext,
        update: @escaping (ModelCapabilityProbeStep, ModelCapabilityProbeStatus, String?) -> Void
    ) async throws -> ModelCapabilityProbeSummary {
        let config = try fetchAPIConfig(company: company, context: context)
        let baseName = restoreBaseModelName(from: modelId)
        var capabilities = ModelCapabilities(
            supportsTextGen: false,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportReasoningChange: false,
            supportsImageGen: false,
            supportsVoiceGen: false,
            supportsToolUse: false
        )

        update(.textGen, .running, nil)
        let textResult = await probeTextGen(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
        switch textResult {
        case .success:
            capabilities.supportsTextGen = true
            update(.textGen, .success, nil)
        case .failure(let message):
            update(.textGen, .failure, message)
        }

        update(.vision, .running, nil)
        if capabilities.supportsTextGen {
            let visionResult = await probeVision(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
            switch visionResult {
            case .success:
                capabilities.supportsMultimodal = true
                update(.vision, .success, nil)
            case .failure(let message):
                update(.vision, .failure, message)
            }
        } else {
            update(.vision, .failure, "文本生成不可用，已跳过")
        }

        update(.reasoning, .running, nil)
        if capabilities.supportsTextGen {
            let reasoningResult = await probeReasoning(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
            switch reasoningResult {
            case .success:
                capabilities.supportsReasoning = true
                update(.reasoning, .success, nil)
            case .failure(let message):
                update(.reasoning, .failure, message)
            }
        } else {
            update(.reasoning, .failure, "文本生成不可用，已跳过")
        }

        update(.reasoningControl, .running, nil)
        if capabilities.supportsReasoning {
            let controlResult = await probeReasoningControl(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
            switch controlResult {
            case .success:
                capabilities.supportReasoningChange = true
                update(.reasoningControl, .success, nil)
            case .failure(let message):
                update(.reasoningControl, .failure, message)
            }
        } else {
            update(.reasoningControl, .failure, "深度思考不可用，已跳过")
        }

        update(.toolUse, .running, nil)
        if capabilities.supportsTextGen {
            let toolResult = await probeToolUse(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
            switch toolResult {
            case .success:
                capabilities.supportsToolUse = true
                update(.toolUse, .success, nil)
            case .failure(let message):
                update(.toolUse, .failure, message)
            }
        } else {
            update(.toolUse, .failure, "文本生成不可用，已跳过")
        }

        update(.imageGen, .running, nil)
        let imageResult = await probeImageGen(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
        switch imageResult {
        case .success:
            capabilities.supportsImageGen = true
            update(.imageGen, .success, nil)
        case .failure(let message):
            update(.imageGen, .failure, message)
        }

        update(.voiceGen, .running, nil)
        if capabilities.supportsTextGen {
            let voiceResult = await probeVoiceGen(baseName: baseName, company: company, requestURL: config.requestURL, apiKey: config.apiKey)
            switch voiceResult {
            case .success:
                capabilities.supportsVoiceGen = true
                update(.voiceGen, .success, nil)
            case .failure(let message):
                update(.voiceGen, .failure, message)
            }
        } else {
            update(.voiceGen, .failure, "文本生成不可用，已跳过")
        }

        return ModelCapabilityProbeSummary(capabilities: capabilities)
    }

    private static func fetchAPIConfig(company: String, context: ModelContext) throws -> (apiKey: String, requestURL: String) {
        let predicate = #Predicate<APIKeys> { $0.company == company }
        let fetchDescriptor = FetchDescriptor<APIKeys>(predicate: predicate)
        guard let key = try? context.fetch(fetchDescriptor).first else {
            throw ModelCapabilityProbeError.invalidAPIKey
        }
        guard let apiKey = key.key, !apiKey.isEmpty else {
            throw ModelCapabilityProbeError.invalidAPIKey
        }
        guard let requestURL = key.requestURL, !requestURL.isEmpty else {
            throw ModelCapabilityProbeError.invalidURL
        }
        return (apiKey, requestURL)
    }

    private static func probeTextGen(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "测试"]
        ]
        let requestBody: [String: Any] = [
            "model": baseName,
            "messages": messages,
            "stream": false,
            "max_tokens": 1
        ]
        return await performChatRequest(requestURL: requestURL, apiKey: apiKey, body: requestBody)
    }

    private static func probeVision(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        // 包含 "AI-HLY" 文字的测试图像 (200x80 白底黑字)
        let base64Image = "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"
        
        var imageUrlValue: [String: Any] = [:]
        if company == "ZHIPUAI" || company == "HANLIN" {
            imageUrlValue["url"] = base64Image
        } else if company == "XAI" {
            imageUrlValue["url"] = "data:image/png;base64,\(base64Image)"
            imageUrlValue["detail"] = "high"
        } else {
            imageUrlValue["url"] = "data:image/png;base64,\(base64Image)"
        }

        let content: [[String: Any]] = [
            ["type": "image_url", "image_url": imageUrlValue],
            ["type": "text", "text": "请识别图片中的文字内容，直接输出文字即可"]
        ]
        let messages: [[String: Any]] = [
            ["role": "user", "content": content]
        ]
        let requestBody: [String: Any] = [
            "model": baseName,
            "messages": messages,
            "stream": false,
            "max_tokens": 64  // 只需要识别简短的文字
        ]
        
        let result = await performChatRequestWithData(requestURL: requestURL, apiKey: apiKey, body: requestBody)
        switch result {
        case .success(let data):
            // 验证返回内容是否包含 AI-HLY 相关文字
            if hasVisionContent(in: data) {
                return .success
            } else {
                return .failure("未能正确识别图像内容")
            }
        case .failure(let message):
            return .failure(message)
        }
    }
    
    /// 检查视觉识别结果是否包含预期的文字
    private static func hasVisionContent(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return false
        }
        
        // 检查返回内容是否包含 AI-HLY 或其变体
        let normalizedContent = content.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        
        // 检查多种可能的识别结果
        if normalizedContent.contains("AIHLY") ||
           normalizedContent.contains("AI_HLY") ||
           (normalizedContent.contains("AI") && normalizedContent.contains("HLY")) {
            return true
        }
        
        return false
    }

    private static func probeReasoning(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        var messages: [[String: Any]] = [
            ["role": "user", "content": "1+1等于几?请简单思考后作答"]
        ]
        var requestBody: [String: Any] = [
            "model": baseName,
            "messages": messages,
            "stream": true,  // 使用流式请求
            "max_tokens": 1024
        ]
        applyThinkingParameters(company: company, enabled: true, requestBody: &requestBody, messages: &messages)
        requestBody["messages"] = messages
        
        // 使用流式请求，一旦检测到思考内容就中断
        return await performStreamingReasoningProbe(requestURL: requestURL, apiKey: apiKey, body: requestBody)
    }
    
    /// 流式探测思考能力，一旦检测到思考内容立即返回成功
    private static func performStreamingReasoningProbe(requestURL: String, apiKey: String, body: [String: Any]) async -> ModelCapabilityProbeResult {
        guard let url = URL(string: requestURL) else {
            return .failure("无效的请求地址")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("响应格式错误")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure("HTTP \(httpResponse.statusCode)")
            }
            
            // 逐行读取流式响应
            for try await line in bytes.lines {
                // SSE 格式: data: {...}
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                
                // 跳过 [DONE] 标记
                if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                    continue
                }
                
                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                // 检查流式响应中的思考内容
                if hasReasoningContentInStreamChunk(json) {
                    // 检测到思考内容，立即返回成功（取消剩余流）
                    return .success
                }
            }
            
            // 流结束但未检测到思考内容
            return .failure("未检测到思考内容")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    
    /// 检查流式响应块中是否包含思考内容
    private static func hasReasoningContentInStreamChunk(_ json: [String: Any]) -> Bool {
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return false
        }
        
        // 检查 reasoning_content 字段 (DeepSeek/Qwen/OpenAI 等)
        if let reasoningContent = delta["reasoning_content"] as? String, !reasoningContent.isEmpty {
            return true
        }
        
        // 检查 thinking 字段 (部分厂商)
        if let thinking = delta["thinking"] as? String, !thinking.isEmpty {
            return true
        }
        
        // 检查 reasoning 字段
        if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
            return true
        }
        
        // 检查 content 中是否包含 <think> 标签开头 (某些开源模型)
        if let content = delta["content"] as? String, content.contains("<think>") {
            return true
        }
        
        return false
    }

    private static func probeReasoningControl(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        // 第一步：测试开启思考模式，应该返回思考内容（使用流式快速检测）
        var messagesOn: [[String: Any]] = [
            ["role": "user", "content": "1+1等于几?"]
        ]
        var requestBodyOn: [String: Any] = [
            "model": baseName,
            "messages": messagesOn,
            "stream": true,
            "max_tokens": 1024
        ]
        applyThinkingParameters(company: company, enabled: true, requestBody: &requestBodyOn, messages: &messagesOn)
        requestBodyOn["messages"] = messagesOn
        
        let onResult = await performStreamingReasoningProbe(requestURL: requestURL, apiKey: apiKey, body: requestBodyOn)
        switch onResult {
        case .success:
            break // 开启时有思考内容，继续测试关闭
        case .failure(let message):
            return .failure("开启模式测试失败: \(message)")
        }

        // 第二步：测试关闭思考模式，应该不返回思考内容
        var messagesOff: [[String: Any]] = [
            ["role": "user", "content": "1+1等于几?"]
        ]
        var requestBodyOff: [String: Any] = [
            "model": baseName,
            "messages": messagesOff,
            "stream": true,
            "max_tokens": 256  // 关闭模式不需要太多 token
        ]
        applyThinkingParameters(company: company, enabled: false, requestBody: &requestBodyOff, messages: &messagesOff)
        requestBodyOff["messages"] = messagesOff
        
        // 关闭模式时，检测是否没有思考内容
        let offResult = await performStreamingReasoningProbeForOff(requestURL: requestURL, apiKey: apiKey, body: requestBodyOff)
        switch offResult {
        case .success:
            // 关闭时没有思考内容 = 可控
            return .success
        case .failure(let message):
            return .failure(message)
        }
    }
    
    /// 流式探测关闭思考模式，确认没有思考内容
    private static func performStreamingReasoningProbeForOff(requestURL: String, apiKey: String, body: [String: Any]) async -> ModelCapabilityProbeResult {
        guard let url = URL(string: requestURL) else {
            return .failure("无效的请求地址")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("响应格式错误")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure("HTTP \(httpResponse.statusCode)")
            }
            
            var hasReceivedContent = false
            var chunkCount = 0
            
            // 逐行读取流式响应，检查前几个 chunk 是否有思考内容
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                
                if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                    break
                }
                
                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                chunkCount += 1
                
                // 如果检测到思考内容，说明关闭模式失败
                if hasReasoningContentInStreamChunk(json) {
                    return .failure("关闭思考模式后仍有思考内容")
                }
                
                // 检查是否有普通内容（说明模型正常响应）
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: Any],
                   let content = delta["content"] as? String,
                   !content.isEmpty {
                    hasReceivedContent = true
                }
                
                // 检查足够多的 chunk 后就可以判断（前 10 个 chunk 没有思考内容就认为成功）
                if chunkCount >= 10 && hasReceivedContent {
                    return .success
                }
            }
            
            // 流结束，没有检测到思考内容
            if hasReceivedContent {
                return .success
            } else {
                return .failure("未收到有效响应")
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func probeToolUse(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        // 定义一个简单的测试工具
        let testTool: [String: Any] = [
            "type": "function",
            "function": [
                "name": "get_current_time",
                "description": "获取当前时间。当用户询问现在几点或当前时间时，调用此工具。",
                "parameters": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ]
        ]
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": "现在几点了？请调用工具获取当前时间。"]
        ]
        let requestBody: [String: Any] = [
            "model": baseName,
            "messages": messages,
            "stream": false,
            "max_tokens": 256,
            "tools": [testTool],
            "tool_choice": "auto"  // 让模型自动决定是否调用工具
        ]
        
        let result = await performChatRequestWithData(requestURL: requestURL, apiKey: apiKey, body: requestBody)
        switch result {
        case .success(let data):
            // 验证返回是否包含 tool_calls
            if hasToolCalls(in: data) {
                return .success
            } else {
                return .failure("未检测到工具调用")
            }
        case .failure(let message):
            return .failure(message)
        }
    }
    
    /// 检查响应数据中是否包含工具调用
    private static func hasToolCalls(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            return false
        }
        
        // 检查 tool_calls 数组是否存在且非空
        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            return true
        }
        
        // 某些厂商可能使用 function_call 字段
        if let functionCall = message["function_call"] as? [String: Any], !functionCall.isEmpty {
            return true
        }
        
        return false
    }

    private static func probeImageGen(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        let prompt = "生成一张测试图片"
        let resolvedURLString = requestURL.contains("chat/completions")
            ? requestURL.replacingOccurrences(of: "chat/completions", with: "images/generations")
            : requestURL
        guard let requestURL = URL(string: resolvedURLString) else {
            return .failure("无效的请求地址")
        }

        var url = requestURL
        var request = URLRequest(url: url)
        var requestBody: [String: Any] = [:]

        switch company {
        case "QWEN":
            url = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis") ?? requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
            requestBody = [
                "model": baseName,
                "input": ["prompt": prompt],
                "parameters": ["size": "1024*1024", "n": 1]
            ]
        case "ZHIPUAI", "HANLIN":
            url = URL(string: "https://open.bigmodel.cn/api/paas/v4/images/generations") ?? requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "size": "1024x1024",
                "prompt": prompt
            ]
        case "SILICONCLOUD", "HANLIN_OPEN":
            url = URL(string: "https://api.siliconflow.cn/v1/images/generations") ?? requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "prompt": prompt,
                "batch_size": 1
            ]
        case "OPENAI":
            url = URL(string: "https://api.openai.com/v1/images/generations") ?? requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "prompt": prompt,
                "n": 1,
                "size": "1024x1024"
            ]
        case "GOOGLE":
            url = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/images/generations") ?? requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "prompt": prompt,
                "n": 1
            ]
        case "XAI":
            url = URL(string: "https://api.x.ai/v1/images/generations") ?? requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "prompt": prompt,
                "n": 1
            ]
        case "MODELSCOPE":
            url = requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "prompt": prompt
            ]
        default:
            url = requestURL
            request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            requestBody = [
                "model": baseName,
                "prompt": prompt
            ]
        }

        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
        return await performRequest(request: request)
    }

    private static func probeVoiceGen(baseName: String, company: String, requestURL: String, apiKey: String) async -> ModelCapabilityProbeResult {
        let messages: [[String: Any]] = [
            ["role": "user", "content": "你好"]
        ]
        let requestBody: [String: Any] = [
            "model": baseName,
            "messages": messages,
            "stream": true,  // 使用流式请求检测音频
            "max_tokens": 64,
            "modalities": ["text", "audio"],
            "audio": [
                "voice": "Cherry",
                "format": "wav"
            ]
        ]
        
        // 使用流式请求，一旦检测到音频分片就中断
        return await performStreamingVoiceProbe(requestURL: requestURL, apiKey: apiKey, body: requestBody)
    }
    
    /// 流式探测语音生成能力，一旦检测到音频分片立即返回成功
    private static func performStreamingVoiceProbe(requestURL: String, apiKey: String, body: [String: Any]) async -> ModelCapabilityProbeResult {
        guard let url = URL(string: requestURL) else {
            return .failure("无效的请求地址")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("响应格式错误")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                return .failure("HTTP \(httpResponse.statusCode)")
            }
            
            // 逐行读取流式响应
            for try await line in bytes.lines {
                // SSE 格式: data: {...}
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                
                // 跳过 [DONE] 标记
                if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                    continue
                }
                
                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                
                // 检查流式响应中的音频内容
                if hasAudioContentInStreamChunk(json) {
                    // 检测到音频内容，立即返回成功（取消剩余流）
                    return .success
                }
            }
            
            // 流结束但未检测到音频内容
            return .failure("未检测到音频数据")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
    
    /// 检查流式响应块中是否包含音频内容
    private static func hasAudioContentInStreamChunk(_ json: [String: Any]) -> Bool {
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return false
        }
        
        // 检查 delta["audio"] 字段（流式音频分片）
        if let audioDelta = delta["audio"] as? [String: Any] {
            // 检查是否有 data 分片
            if let audioData = audioDelta["data"] as? String, !audioData.isEmpty {
                return true
            }
            // 检查是否有 transcript 转录文本
            if let transcript = audioDelta["transcript"] as? String, !transcript.isEmpty {
                return true
            }
        }
        
        return false
    }

    private static func applyThinkingParameters(
        company: String,
        enabled: Bool,
        requestBody: inout [String: Any],
        messages: inout [[String: Any]]
    ) {
        if company == "QWEN" || company == "MODELSCOPE" || company == "SILICONCLOUD" || company == "WENXIN" {
            requestBody["enable_thinking"] = enabled
        } else if company == "ANTHROPIC" {
            requestBody["think"] = ["type": enabled ? "enabled" : "disabled"]
        } else if company == "ZHIPUAI" || company == "HANLIN" || company == "DOUBAO" || company == "OPENROUTER" {
            requestBody["thinking"] = ["type": enabled ? "enabled" : "disabled"]
        } else {
            if var lastMessage = messages.last,
               let content = lastMessage["content"] as? String,
               !content.contains("/think"),
               !content.contains("/no_think") {
                lastMessage["content"] = enabled ? "\(content) /think" : "\(content) /no_think"
                messages[messages.count - 1] = lastMessage
            }
        }
    }

    private static func performChatRequest(requestURL: String, apiKey: String, body: [String: Any]) async -> ModelCapabilityProbeResult {
        guard let url = URL(string: requestURL) else {
            return .failure("无效的请求地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return await performRequest(request: request)
    }

    /// 执行 Chat 请求并返回响应数据（用于需要验证响应内容的探测）
    private static func performChatRequestWithData(requestURL: String, apiKey: String, body: [String: Any]) async -> ModelCapabilityProbeResultWithData {
        guard let url = URL(string: requestURL) else {
            return .failure("无效的请求地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // 思考模型可能需要更长时间
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return await performRequestWithData(request: request)
    }

    private static func performRequest(request: URLRequest) async -> ModelCapabilityProbeResult {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("响应格式错误")
            }
            if (200...299).contains(httpResponse.statusCode) {
                return .success
            }
            return .failure("HTTP \(httpResponse.statusCode)")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// 执行请求并返回原始数据
    private static func performRequestWithData(request: URLRequest) async -> ModelCapabilityProbeResultWithData {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("响应格式错误")
            }
            if (200...299).contains(httpResponse.statusCode) {
                return .success(data: data)
            }
            return .failure("HTTP \(httpResponse.statusCode)")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: 添加模型到数据库
    static func addModelToDatabase(
        modelId: String,
        displayName: String,
        company: String,
        context: ModelContext,
        capabilities: ModelCapabilities? = nil
    ) throws {
        // 检查是否已存在
        let targetName = modelId + "_repeat_" + company
        let fetchDescriptor = FetchDescriptor<AllModels>(
            predicate: #Predicate { model in
                model.name == targetName
            }
        )

        let existingModels = try context.fetch(fetchDescriptor)
        guard existingModels.isEmpty else {
            throw ModelFetchError.modelAlreadyExists
        }

        // 获取下一个位置
        let allModelsDescriptor = FetchDescriptor<AllModels>()
        let allModels = try context.fetch(allModelsDescriptor)
        let nextPosition = (allModels.map { $0.position ?? 999 }.max() ?? 0) + 1

        let resolvedCapabilities = capabilities ?? ModelCapabilities(
            supportsTextGen: true,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportReasoningChange: false,
            supportsImageGen: false,
            supportsVoiceGen: false,
            supportsToolUse: false
        )

        // 创建新模型
        let newModel = AllModels(
            name: modelId + "_repeat_" + company,
            displayName: displayName,
            identity: "model",
            position: nextPosition,
            company: company,
            price: 2, // 默认适中价格
            isHidden: false,
            supportsSearch: false,
            supportsTextGen: resolvedCapabilities.supportsTextGen,
            supportsMultimodal: resolvedCapabilities.supportsMultimodal,
            supportsReasoning: resolvedCapabilities.supportsReasoning,
            supportReasoningChange: resolvedCapabilities.supportReasoningChange,
            supportsImageGen: resolvedCapabilities.supportsImageGen,
            supportsVoiceGen: resolvedCapabilities.supportsVoiceGen,
            supportsToolUse: resolvedCapabilities.supportsToolUse,
            systemProvision: false // 用户添加的模型
        )

        context.insert(newModel)
        try context.save()
    }

    // MARK: 从数据库删除模型
    static func removeModelFromDatabase(
        modelName: String,
        context: ModelContext
    ) throws {
        let targetName = modelName
        let fetchDescriptor = FetchDescriptor<AllModels>(
            predicate: #Predicate { model in
                model.name == targetName
            }
        )

        let models = try context.fetch(fetchDescriptor)
        for model in models {
            // 只能删除非系统预置的模型
            if !model.systemProvision {
                context.delete(model)
            }
        }

        try context.save()
    }
}

// MARK: - 错误定义
enum ModelFetchError: LocalizedError {
    case invalidAPIKey
    case invalidCompany
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
    case modelAlreadyExists
    case systemModelCannotBeDeleted

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "无效的 API 密钥"
        case .invalidCompany:
            return "无效的厂商信息"
        case .invalidURL:
            return "无效的请求地址"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let statusCode):
            return "HTTP 错误: \(statusCode)"
        case .decodingError:
            return "解析响应失败"
        case .modelAlreadyExists:
            return "模型已存在"
        case .systemModelCannotBeDeleted:
            return "系统预置模型无法删除"
        }
    }
}