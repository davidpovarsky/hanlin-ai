//
//  CanvasServices.swift
//  AI_Hanlin
//
//  Created by 哆啦好多梦 on 18/5/25.
//

import Foundation
import SwiftData
import LLM

/// CanvasService 相关错误
enum CanvasServiceError: Error {
    /// 保存到持久化存储失败
    case saveFailed(Error)
}

/// 管理 CanvasData 的创建与保存
@MainActor
class CanvasServices {
    /// 创建一个新的 CanvasData（尚未保存到任何 ChatRecords）
    ///
    /// - Parameters:
    ///   - title:   画布标题
    ///   - content: 初始文字内容
    ///   - type:    画布类型
    /// - Returns: 一个 `id == nil`、`saved == false` 的 `CanvasData`
    static func createCanvasData(
        title: String,
        content: String = "",
        type: String = ""
    ) -> CanvasData {
        CanvasData(
            title: title,
            content: content,
            type: type,
            saved: false,
            id: nil,
            history: [content],
            index: 0,
        )
    }
    
    /// 将一个 CanvasData 保存到指定的 ChatRecords 中，并持久化
    ///
    /// - Parameters:
    ///   - canvas:     要保存的 `CanvasData`
    ///   - chatRecord: 目标 `ChatRecords` 实例
    ///   - context:    SwiftData 的 ModelContext
    /// - Returns: 更新后、带有非空 `id`、`saved == true`、并合并了历史记录的 `CanvasData`
    /// - Throws: `CanvasServiceError.saveFailed` 当持久化失败时
    static func saveCanvas(
        _ canvas: CanvasData,
        to chatRecord: ChatRecords,
        in context: ModelContext
    ) throws -> CanvasData {
        var updated = canvas

        // 1. 确保 ID
        if updated.id == nil {
            updated.id = UUID()
        }

        // 3. 合并历史记录
        var hist = updated.history ?? []
        let curIdx = updated.index ?? -1
        // 如果历史为空，初始化
        if hist.isEmpty {
            hist = [updated.content]
            updated.index = 0
        } else {
            // 如果当前 content 与历史当前快照不同，就追加
            let safeIdx = min(max(curIdx, 0), hist.count - 1)
            if hist[safeIdx] != updated.content {
                // 丢弃“前进”分支
                let prefix = hist.prefix(safeIdx + 1)
                hist = Array(prefix)
                // 追加新快照
                hist.append(updated.content)
                updated.index = hist.count - 1
            } else {
                // 内容未变，则保持原 index
                updated.index = safeIdx
            }
        }
        updated.history = hist

        // 4. 写入 chatRecord 并持久化
        chatRecord.canvas = updated
        do {
            try context.save()
            return updated
        } catch {
            throw CanvasServiceError.saveFailed(error)
        }
    }
    
    /// 修改已有画布的内容，可用于模型工具调用实现替换、插入、删除等操作（支持多条替换规则）
    ///
    /// - Parameters:
    ///   - canvas: 原始 CanvasData
    ///   - rules: 替换规则数组，每条包含 pattern 和 replacement
    /// - Returns: 修改后的 CanvasData（不会直接保存）
    /// - Throws: 正则表达式无效时抛出错误
    static func editCanvasContent(
        canvas: CanvasData,
        rules: [(pattern: String, replacement: String)]
    ) throws -> CanvasData {
        var updated = canvas
        var content = canvas.content
        var title = canvas.title
        
        for (pattern, replacement) in rules {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                
                // 替换 content
                let contentRange = NSRange(location: 0, length: content.utf16.count)
                content = regex.stringByReplacingMatches(
                    in: content,
                    options: [],
                    range: contentRange,
                    withTemplate: replacement
                )
                
                // 替换 title（使用 title 的 range）
                let titleRange = NSRange(location: 0, length: title.utf16.count)
                title = regex.stringByReplacingMatches(
                    in: title,
                    options: [],
                    range: titleRange,
                    withTemplate: replacement
                )
            } catch {
                throw CanvasServiceError.saveFailed(error)
            }
        }
        
        updated.content = content
        updated.title = title
        updated.saved = false
        
        var hist = updated.history ?? []
        let curIdx = updated.index ?? 0
        
        if curIdx < hist.count - 1 {
            hist = Array(hist.prefix(curIdx + 1))
        }
        
        hist.append(content)
        updated.history = hist
        updated.index = hist.count - 1
        
        return updated
    }
}

// MARK: 后端流式接口
@MainActor
func editCanvasAPI(
    input: String,
    modelInfo: AllModels,
    readingLevel: String,
    lengthOption: String,
    apiKey: String,
    requestURL: String
) async throws -> AsyncThrowingStream<String, Error> {
    // 1) 构造提示
    let currentLanguage = Locale.preferredLanguages.first ?? "zh"
    let systemInfo: String = {
        if modelInfo.identity == "agent" {
            return currentLanguage.hasPrefix("zh")
                ? "# 你是【\(modelInfo.displayName ?? "智能助手")】。\n#你被设定为：\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "智能助手")")\n请记住你的设定，在回复时保证始终遵循这个设定!"
                : "# You are [\(modelInfo.displayName ?? "AI assistant")].\n# You have been configured as:\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "AI assistant")")\nPlease remember your configuration and always adhere to it when replying!"
        } else {
            return currentLanguage.hasPrefix("zh")
                ? "# 你是高级作家，能将文本按指定要求改写。"
                : "# You are an advanced writer who can rewrite text to specified requirements."
        }
    }()
    var userPrompt: String = {
        if currentLanguage.hasPrefix("zh") {
            return """
            请根据阅读水平和长度要求改写画布内容，要求为空的项说明对此项不做限制。
            注意：改写时注意严格保留原有内容的特征、句式、题材、格式等。
            要求：直接给出改写后的内容，不要添加任何解释说明。
            阅读水平：\(readingLevel)
            长度要求：\(lengthOption)

            现有画布内容：
            \(input)
            """
        } else {
            return """
            Please rewrite the canvas content according to the reading level and length requirements. For items left blank, no restrictions apply.
            Note: When rewriting, strictly preserve the original content's characteristics, sentence structure, subject matter, format, etc.
            Requirement: Provide only the rewritten content without any additional explanations.
            Reading level: \(readingLevel)
            Length requirement: \(lengthOption)

            Original canvas content:
            \(input)
            """
        }
    }()
    
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
                        temp: 0.3
                    ) else {
                        throw NSError(domain: "LocalLLMInit", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地 LLM 初始化失败"])
                    }
                    
                    var accumulatedOutput = ""
                    
                    // 调用本地模型流式接口，传入翻译提示
                    await llm.respond(to: userPrompt) { responseStream in
                        for await delta in responseStream {
                            accumulatedOutput += delta
                            // 输出本地模型返回的 token
                            continuation.yield(delta)
                            
                            // 检测输出中是否出现停止标记，提前结束生成
                            if accumulatedOutput.contains("<|im_end|>") || accumulatedOutput.contains("<|im_start|>") {
                                llm.stop()
                                break
                            }
                        }
                        return ""
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // 3) 远程模型调用
    guard !apiKey.isEmpty else {
        throw NSError(domain: "ConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey:"无效 API Key"])
    }
    guard let url = URL(string: requestURL) else {
        throw NSError(domain: "ConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey:"无效请求 URL"])
    }
    
    // 构造 Chat 完整消息
    let systemRole = modelInfo.company == "OPENAI" ? "developer" : "system"
    if let name = modelInfo.name?.lowercased(), name.contains("qwen3") {
        userPrompt = "/no_think\n" + userPrompt
    }
    let messages: [[String: Any]] = [
        ["role": systemRole, "content": systemInfo],
        ["role": "user",     "content": userPrompt]
    ]
    // 4) 开启流式
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let body: [String: Any] = [
        "model": restoreBaseModelName(from: modelInfo.name ?? "Unknown"),
        "messages": messages,
        "temperature": 0.3,
        "stream": true
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
    
    // 5) 发起 streaming 请求
    let (result, response) = try await URLSession.shared.bytes(for: req)
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

/// 对选中片段进行智能改写
@MainActor
func refineSelectedTextAPI(
    fullText: String,           // 整体上下文原文
    selectedText: String,       // 被选中的片段
    suggestion: String,         // 用户修改意见
    modelInfo: AllModels,
    apiKey: String,
    requestURL: String
) async throws -> AsyncThrowingStream<String, Error> {
    let currentLanguage = Locale.preferredLanguages.first ?? "zh"
    
    // Agent/助手人格设定
    let systemInfo: String = {
        if modelInfo.identity == "agent" {
            return currentLanguage.hasPrefix("zh")
                ? "# 你是【\(modelInfo.displayName ?? "智能助手")】。\n# 你被设定为：\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "智能助手")")\n请记住你的设定，在回复时保证始终遵循这个设定!"
                : "# You are [\(modelInfo.displayName ?? "AI assistant")].\n# You have been configured as:\n\(modelInfo.characterDesign ?? "\(modelInfo.displayName ?? "AI assistant")")\nPlease remember your configuration and always adhere to it when replying!"
        } else {
            return currentLanguage.hasPrefix("zh")
                ? "# 你是无所不能的专业助手，既精通文学，又擅长代码。请根据用户意见对选中片段进行改写。"
                : "# You are an advanced text rewriting assistant. Please revise the selected segment according to the user's suggestion."
        }
    }()
    
    var userPrompt: String = {
        if currentLanguage.hasPrefix("zh") {
            return """
            现有全文内容如下（供参考）：
            \(fullText)
            
            你的任务是：仅对下方“选中片段”进行针对性修改，其余内容不做处理。
            选中片段如下：
            \(selectedText)
            
            用户的修改意见：
            \(suggestion)
            
            要求：直接输出改写后的用于替换原文选中部分的片段，不要加任何解释说明或格式。
            """
        } else {
            return """
            Here is the full content for context:
            \(fullText)
            
            Your task: ONLY revise the SELECTED segment below according to the user's revision suggestion. Do not touch other content.
            Selected segment:
            \(selectedText)
            
            User's suggestion:
            \(suggestion)
            
            Requirement: Directly output the rewritten segment to replace the originally selected part, without any explanations or formatting.
            """
        }
    }()
    
    // —— 本地模型分支 ——
    if apiKey.uppercased() == "LOCAL" || requestURL.uppercased() == "LOCAL" {
        return AsyncThrowingStream<String, Error> { continuation in
            Task(priority: .userInitiated) {
                do {
                    guard let modelPath = getLocalModelPath(for: modelInfo.name ?? "Unknown") else {
                        throw NSError(domain: "LocalModelError", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到本地模型路径"])
                    }
                    guard let llm = LLM(
                        from: URL(fileURLWithPath: modelPath),
                        template: .chatML(systemInfo),
                        temp: 0.2
                    ) else {
                        throw NSError(domain: "LocalLLMInit", code: -1, userInfo: [NSLocalizedDescriptionKey: "本地 LLM 初始化失败"])
                    }
                    var accumulatedOutput = ""
                    await llm.respond(to: userPrompt) { responseStream in
                        for await delta in responseStream {
                            accumulatedOutput += delta
                            continuation.yield(delta)
                            if accumulatedOutput.contains("<|im_end|>") || accumulatedOutput.contains("<|im_start|>") {
                                llm.stop()
                                break
                            }
                        }
                        return ""
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // —— 远程模型分支 ——
    guard !apiKey.isEmpty else {
        throw NSError(domain: "ConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey:"无效 API Key"])
    }
    guard let url = URL(string: requestURL) else {
        throw NSError(domain: "ConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey:"无效请求 URL"])
    }
    
    let systemRole = modelInfo.company == "OPENAI" ? "developer" : "system"
    if let name = modelInfo.name?.lowercased(), name.contains("qwen3") {
        userPrompt = "/no_think\n" + userPrompt
    }
    let messages: [[String: Any]] = [
        ["role": systemRole, "content": systemInfo],
        ["role": "user",     "content": userPrompt]
    ]
    
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let body: [String: Any] = [
        "model": restoreBaseModelName(from: modelInfo.name ?? "Unknown"),
        "messages": messages,
        "temperature": 0.2,
        "stream": true
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
    
    let (result, response) = try await URLSession.shared.bytes(for: req)
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
