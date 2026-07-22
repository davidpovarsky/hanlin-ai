//
//  ToolsAPI.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 27/2/25.
//

import Foundation
import SwiftData
@preconcurrency import LLM

// MARK: 翻译文本函数（流式输出版）
@MainActor
func translateTextAPI(
    input: String,
    sourceLanguage: String,
    modelInfo: AllModels,
    targetLanguage: String,
    translationMatters: String,
    apiKey: String,
    requestURL: String
) async throws -> AsyncThrowingStream<String, Error> {
    
    // 构造翻译提示词
    let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
    var translationPrompt: String
    if currentLanguage.hasPrefix("zh") {
        translationPrompt = """
        请将输入的文本从 \(sourceLanguage) 翻译为 \(targetLanguage)，保留原意，确保自然流畅，符合地道目标语言的表达。直接给出翻译结果的纯文本，不要添加额外信息。
        如果是语言类型为自动检测，则需要你结合语境来判断，一般是中英互译。\(translationMatters)
        输入文本：\n\(input)
        """
    } else {
        translationPrompt = """
        Please translate the input text from \(sourceLanguage) to \(targetLanguage), preserving the original meaning while ensuring fluency and natural expression in the target language. Provide the translation as plain text without any additional information.\(translationMatters)
        If the language type is set to "Automatic detection", you need to determine the context, typically translating between Chinese and English.
        Input text:\n\(input)
        """
    }
    
    var systemInfo = ""
    if modelInfo.identity == "agent" {
        if currentLanguage.hasPrefix("zh") {
            systemInfo = "# 你是【\(modelInfo.displayName ?? "智能助手")】。\n#你被设定为：\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "智能助手")")\n请记住你的设定，在回复时保证始终遵循这个设定!"
        } else {
            systemInfo = "# You are [\(modelInfo.displayName ?? "AI assistant")].\n# You have been configured as:\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "AI assistant")")\nPlease remember your configuration and always adhere to it when replying!"
        }
    } else {
        if currentLanguage.hasPrefix("zh") {
            systemInfo = "# 你是高级翻译助理，能将文本翻译为指定语言，并且翻译地道准确。"
        } else {
            systemInfo = "# You are a Senior Translation Assistant who can translate text into the specified language with authenticity and accuracy."
        }
    }
    
    // 本地模型处理分支
    if apiKey.uppercased() == "LOCAL" || requestURL.uppercased() == "LOCAL" {
        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) {
                do {
                    // 获取本地模型路径
                    guard let modelPath = getLocalModelPath(for: modelInfo.name ?? "Unknown") else {
                        throw NSError(domain: "LocalModelError", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到本地模型路径"])
                    }
                    
                    // 初始化本地 LLM
                    guard let llm = LLM(
                        from: URL(fileURLWithPath: modelPath),
                        template: .chatML(systemInfo),
                        temp: 1.0
                    ) else {
                        throw NSError(domain: "LocalLLMInit", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地 LLM 初始化失败"])
                    }
                    
                    var accumulatedOutput = ""
                    
                    // 调用本地模型流式接口，传入翻译提示
                    await LocalLLMStreamingAdapter.consume(llm, prompt: translationPrompt) { delta in
                            accumulatedOutput += delta
                            // 输出本地模型返回的 token
                            continuation.yield(delta)
                            
                            // 检测输出中是否出现停止标记，提前结束生成
                            if accumulatedOutput.contains("<|im_end|>") || accumulatedOutput.contains("<|im_start|>") {
                                llm.stop()
                                return false
                            }
                            return true
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // 远程处理分支
    // 检查 API Key 与 URL 是否有效
    guard !apiKey.isEmpty else {
        throw NSError(domain: "APIConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API Key"])
    }
    guard let url = URL(string: requestURL), !requestURL.isEmpty else {
        throw NSError(domain: "URLConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的请求 URL"])
    }
    
    // 构造消息
    var formattedMessages: [[String: Any]] = []
    let remoteSystemRole: String = {
        switch modelInfo.company {
        case "OPENAI": return "developer"
        default: return "system"
        }
    }()
    formattedMessages.append([
        "role": remoteSystemRole,
        "content": systemInfo
    ])
    if let name = modelInfo.name?.lowercased(), name.contains("qwen3") {
        translationPrompt = "/no_think\n" + translationPrompt
    }
    formattedMessages.append([
        "role": "user",
        "content": translationPrompt
    ])
    
    let baseName = restoreBaseModelName(from: modelInfo.name ?? "Unknown")
    // 设置 stream 参数为 true 实现流式输出
    let requestBody: [String: Any] = [
        "model": baseName,
        "messages": formattedMessages,
        "temperature": 1.0,
        "stream": true
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
    
    let (result, response) = try await URLSession.shared.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
        throw NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "请求错误: HTTP 状态码 \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
    }
    
    // 解析远程返回的流式数据
    return AsyncThrowingStream<String, Error> { continuation in
        Task {
            do {
                for try await line in result.lines {
                    // 根据 OpenAI 等 API 返回格式：以 "data: " 开头
                    if line.hasPrefix("data: ") {
                        let jsonString = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let jsonData = jsonString.data(using: .utf8),
                              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                              let choices = jsonObject["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let token = delta["content"] as? String else {
                            continue
                        }
                        // 逐步输出 token
                        continuation.yield(token)
                        
                        if let finishReason = choices.first?["finish_reason"] as? String, finishReason == "stop" {
                            break
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}


// MARK: 润色优化函数（流式输出版）
@MainActor
func polishTextAPI(input: String,
                   modelInfo: AllModels,
                   prompts: String,
                   apiKey: String,
                   requestURL: String) async throws -> AsyncThrowingStream<String, Error> {
    // 构造优化提示词
    let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
    var optimizationPrompt: String
    if currentLanguage.hasPrefix("zh") {
        optimizationPrompt = """
        请按照以下要求优化文本，优化时保留原意，确保自然流畅，如果要求为空，则你自行决定优化方向：
        \(prompts)
        直接返回润色后的文本，不要添加额外解释。
        
        现有的文本：
        \(input)
        """
    } else {
        optimizationPrompt = """
        Please refine the text according to the following requirements while preserving its original meaning and ensuring natural fluency. If no specific request is provided, you may decide on the optimization direction yourself:
        \(prompts)
        Return only the polished text without any additional explanations.
        
        Original text:
        \(input)
        """
    }
    
    var systemInfo = ""
    if modelInfo.identity == "agent" {
        if currentLanguage.hasPrefix("zh") {
            systemInfo = "# 你是【\(modelInfo.displayName ?? "智能助手")】。\n#你被设定为：\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "智能助手")")\n请记住你的设定，在回复时保证始终遵循这个设定!"
        } else {
            systemInfo = "# You are [\(modelInfo.displayName ?? "AI assistant")].\n# You have been configured as:\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "AI assistant")")\nPlease remember your configuration and always adhere to it when replying!"
        }
    } else {
        if currentLanguage.hasPrefix("zh") {
            systemInfo = "# 你是高级作家，能将文本按指定要求改写。"
        } else {
            systemInfo = "# You are an advanced writer who can rewrite text to specified requirements."
        }
    }
    
    // 本地模型处理分支
    if apiKey.uppercased() == "LOCAL" || requestURL.uppercased() == "LOCAL" {
        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) {
                do {
                    // 获取本地模型路径
                    guard let modelPath = getLocalModelPath(for: modelInfo.name ?? "Unknown") else {
                        throw NSError(domain: "LocalModelError", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到本地模型路径"])
                    }
                    
                    // 初始化本地 LLM
                    guard let llm = LLM(
                        from: URL(fileURLWithPath: modelPath),
                        template: .chatML(systemInfo),
                        temp: 1.0
                    ) else {
                        throw NSError(domain: "LocalLLMInit", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地 LLM 初始化失败"])
                    }
                    
                    var accumulatedOutput = ""
                    
                    // 调用本地模型流式接口，传入翻译提示
                    await LocalLLMStreamingAdapter.consume(llm, prompt: optimizationPrompt) { delta in
                            accumulatedOutput += delta
                            // 输出本地模型返回的 token
                            continuation.yield(delta)
                            
                            // 检测输出中是否出现停止标记，提前结束生成
                            if accumulatedOutput.contains("<|im_end|>") || accumulatedOutput.contains("<|im_start|>") {
                                llm.stop()
                                return false
                            }
                            return true
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // 远程模型处理逻辑（流式输出版）
    guard !apiKey.isEmpty else {
        throw NSError(domain: "APIConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API Key"])
    }
    guard let url = URL(string: requestURL), !requestURL.isEmpty else {
        throw NSError(domain: "URLConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的请求 URL"])
    }
    
    var formattedMessages: [[String: Any]] = []
    let systemRole: String = {
        switch modelInfo.company {
        case "OPENAI": return "developer"
        default: return "system"
        }
    }()
    formattedMessages.append([
        "role": systemRole,
        "content": systemInfo
    ])
    if let name = modelInfo.name?.lowercased(), name.contains("qwen3") {
        optimizationPrompt = "/no_think\n" + optimizationPrompt
    }
    formattedMessages.append([
        "role": "user",
        "content": optimizationPrompt
    ])
    
    let baseName = restoreBaseModelName(from: modelInfo.name ?? "Unknown")
    
    // 注意：stream 参数置为 true
    let requestBody: [String: Any] = [
        "model": baseName,
        "messages": formattedMessages,
        "temperature": 0.8,
        "stream": true
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
    
    let (result, response) = try await URLSession.shared.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
        throw NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "请求错误: HTTP 状态码 \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
    }
    
    return AsyncThrowingStream<String, Error> { continuation in
        Task {
            do {
                for try await line in result.lines {
                    if line.hasPrefix("data: ") {
                        let jsonString = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let jsonData = jsonString.data(using: .utf8),
                              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                              let choices = jsonObject["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let token = delta["content"] as? String else {
                            continue
                        }
                        continuation.yield(token)
                        if choices.first?["finish_reason"] is String {
                            break
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}


// MARK: 生成摘要函数（流式输出版）
@MainActor
func generateSummaryAPI(input: String,
                        modelInfo: AllModels,
                        apiKey: String,
                        requestURL: String
) async throws -> AsyncThrowingStream<String, Error> {
    
    let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
    var summaryPrompt: String
    if currentLanguage.hasPrefix("zh") {
        summaryPrompt = "请对以下文本生成简洁的摘要，直接返回摘要纯文本，不要添加额外解释：\n\(input)"
    } else {
        summaryPrompt = "Please generate a concise summary for the following text. Return only the summary as plain text without any additional explanations:\n\(input)"
    }
    
    var systemInfo = ""
    if modelInfo.identity == "agent" {
        if currentLanguage.hasPrefix("zh") {
            systemInfo = "# 你是【\(modelInfo.displayName ?? "智能助手")】。\n#你被设定为：\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "智能助手")")\n请记住你的设定，在回复时保证始终遵循这个设定!"
        } else {
            systemInfo = "# You are [\(modelInfo.displayName ?? "AI assistant")].\n# You have been configured as:\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "AI assistant")")\nPlease remember your configuration and always adhere to it when replying!"
        }
    } else {
        if currentLanguage.hasPrefix("zh") {
            systemInfo = "# 你是高级阅读助理，能将长段落文本凝练为要素齐全，详略得当的摘要。"
        } else {
            systemInfo = "# You are an advanced reading assistant who can condense long passages of text into well-elemented, detailed summaries."
        }
    }
    
    // 本地模型处理分支
    if apiKey.uppercased() == "LOCAL" || requestURL.uppercased() == "LOCAL" {
        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) {
                do {
                    // 获取本地模型路径
                    guard let modelPath = getLocalModelPath(for: modelInfo.name ?? "Unknown") else {
                        throw NSError(domain: "LocalModelError", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到本地模型路径"])
                    }
                    
                    // 初始化本地 LLM
                    guard let llm = LLM(
                        from: URL(fileURLWithPath: modelPath),
                        template: .chatML(systemInfo),
                        temp: 1.0
                    ) else {
                        throw NSError(domain: "LocalLLMInit", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地 LLM 初始化失败"])
                    }
                    
                    var accumulatedOutput = ""
                    
                    // 调用本地模型流式接口，传入翻译提示
                    await LocalLLMStreamingAdapter.consume(llm, prompt: summaryPrompt) { delta in
                            accumulatedOutput += delta
                            // 输出本地模型返回的 token
                            continuation.yield(delta)
                            
                            // 检测输出中是否出现停止标记，提前结束生成
                            if accumulatedOutput.contains("<|im_end|>") || accumulatedOutput.contains("<|im_start|>") {
                                llm.stop()
                                return false
                            }
                            return true
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // 远程模型处理逻辑（流式输出版）
    guard !apiKey.isEmpty else {
        throw NSError(domain: "APIConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API Key"])
    }
    guard let url = URL(string: requestURL), !requestURL.isEmpty else {
        throw NSError(domain: "URLConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的请求 URL"])
    }
    
    var formattedMessages: [[String: Any]] = []
    let systemRole: String = {
        switch modelInfo.company {
        case "OPENAI": return "developer"
        default: return "system"
        }
    }()
    formattedMessages.append([
        "role": systemRole,
        "content": systemInfo
    ])
    if let name = modelInfo.name?.lowercased(), name.contains("qwen3") {
        summaryPrompt = "/no_think\n" + summaryPrompt
    }
    formattedMessages.append([
        "role": "user",
        "content": summaryPrompt
    ])
    
    let baseName = restoreBaseModelName(from: modelInfo.name ?? "Unknown")
    let requestBody: [String: Any] = [
        "model": baseName,
        "messages": formattedMessages,
        "temperature": 0.6,
        "stream": true  // 开启流式输出
    ]
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
    
    let (result, response) = try await URLSession.shared.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
        throw NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "请求错误: HTTP 状态码 \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
    }
    
    return AsyncThrowingStream<String, Error> { continuation in
        Task {
            do {
                for try await line in result.lines {
                    if line.hasPrefix("data: ") {
                        let jsonString = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let jsonData = jsonString.data(using: .utf8),
                              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                              let choices = jsonObject["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let token = delta["content"] as? String else {
                            continue
                        }
                        continuation.yield(token)
                        if choices.first?["finish_reason"] is String {
                            break
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
