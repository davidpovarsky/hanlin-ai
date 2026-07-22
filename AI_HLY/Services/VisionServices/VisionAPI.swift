//
//  Services/APIManager.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 4/2/25.
//

import Foundation
import PhotosUI
import SwiftData

// MARK: - 数据结构定义
struct VisionStreamData {
    var content: String?    // 回复内容
    var reasoning: String?  // 推理/思考过程
}

@MainActor
class VisionAPIManager {
    
    private var context: ModelContext
    
    init(context: ModelContext) {
        self.context = context
    }
    
    func getAPIKey(for company: String, context: ModelContext) -> String? {
        let predicate = #Predicate<APIKeys> { $0.company == company }
        let fetchDescriptorFiltered = FetchDescriptor<APIKeys>(predicate: predicate)
        if let result = try? context.fetch(fetchDescriptorFiltered).first {
            return result.key
        }
        return nil
    }
    
    func getRequestURL(for company: String, context: ModelContext) -> String? {
        let predicate = #Predicate<APIKeys> { $0.company == company }
        let fetchDescriptor = FetchDescriptor<APIKeys>(predicate: predicate)
        if let result = try? context.fetch(fetchDescriptor).first {
            return result.requestURL
        }
        return nil
    }
    
    private var currentTask: URLSessionDataTask? // 记录当前的流式请求任务
    private var isCancelled = false // 标记请求是否被取消

    private func parseRequestErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    return message
                }
                if let detail = error["detail"] as? String, !detail.isEmpty {
                    return detail
                }
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let errorDescription = json["error_description"] as? String, !errorDescription.isEmpty {
                return errorDescription
            }
            if let errors = json["errors"] as? [String], !errors.isEmpty {
                return errors.joined(separator: "\n")
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func readErrorBody(from bytes: URLSession.AsyncBytes, limit: Int = 4096) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                break
            }
        }
        return data
    }
    
    // 终止当前的流式请求
    func cancelCurrentRequest() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - 记忆检索
    private func retrieveMemory(keyword: String) -> String {
        
        // 1. 加载 JSON 配置（仅加载一次）
        let config: (stopWords: Set<String>, stopChars: Set<Character>, synonymMap: [String: [String]]) = {
            guard
                let url = Bundle.main.url(forResource: "memoryConfig", withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ([], [], [:])
            }
            
            let stopWords = Set((json["stopWords"] as? [String]) ?? [])
            let stopChars = Set((json["stopChars"] as? [String] ?? []).compactMap { $0.first })
            let synonymMap = json["synonymMap"] as? [String: [String]] ?? [:]
            
            return (stopWords, stopChars, synonymMap)
        }()
        
        // 1.1 构建双向同义词映射
        var expandedSynonymMap: [String: Set<String>] = [:]
        for (key, values) in config.synonymMap {
            for v in values {
                expandedSynonymMap[key, default: []].insert(v)
                expandedSynonymMap[v, default: []].insert(key)
                for other in values where other != v {
                    expandedSynonymMap[v, default: []].insert(other)
                }
            }
        }
        
        // 2. 分词（去除停用词）
        func tokenize(_ text: String) -> [String] {
            text
                .lowercased()
                .split { $0.isWhitespace || $0.isPunctuation || $0 == ";" || $0 == "；" }
                .map(String.init)
                .filter { !$0.isEmpty && !config.stopWords.contains($0) }
        }
        
        // 3. 编辑距离（拼写相近）
        func levenshtein(_ s: String, _ t: String) -> Int {
            let a = Array(s), b = Array(t)
            var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
            for i in 0...a.count { dp[i][0] = i }
            for j in 0...b.count { dp[0][j] = j }
            for i in 1...a.count {
                for j in 1...b.count {
                    dp[i][j] = min(
                        dp[i-1][j] + 1,
                        dp[i][j-1] + 1,
                        dp[i-1][j-1] + (a[i-1] == b[j-1] ? 0 : 1)
                    )
                }
            }
            return dp[a.count][b.count]
        }
        
        // 4. 解析关键词
        let terms = tokenize(keyword)
        guard !terms.isEmpty else {
            return ""
        }
        
        do {
            let descriptor = FetchDescriptor<MemoryArchive>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            let allMemories = try context.fetch(descriptor)
            
            var scored: [(MemoryArchive, Int)] = []
            
            for mem in allMemories {
                guard let raw = mem.content, !raw.isEmpty else { continue }
                let content = raw.lowercased()
                let words = tokenize(content)
                var score = 0
                
                for term in terms {
                    let isChinese = term.range(of: #"\p{Han}"#, options: .regularExpression) != nil
                    
                    // 1) 完整匹配
                    if content.contains(term) {
                        score += term.count * 4
                    }
                    
                    // 2) 编辑距离匹配
                    for w in words {
                        if abs(w.count - term.count) > 2 { continue }
                        let dist = levenshtein(term, w)
                        if dist <= 2 && dist < term.count {
                            score += max(0, term.count - dist) * 2
                            break
                        }
                    }
                    
                    // 3) 同义词匹配（含双向）
                    if let syns = expandedSynonymMap[term] {
                        for syn in syns where content.contains(syn) {
                            score += term.count
                            break
                        }
                    }
                    
                    // 4) 字符重叠匹配
                    if isChinese && term.count > 1 {
                        for ch in term where !config.stopChars.contains(ch) {
                            if content.contains(ch) {
                                score += 1
                            }
                        }
                    }
                    
                    if !isChinese && term.count > 1 {
                        for ch in term where !config.stopChars.contains(ch) && ch.isLetter {
                            if content.contains(ch) {
                                score += 1
                            }
                        }
                    }
                }
                
                if score > 0 {
                    scored.append((mem, score))
                }
            }
            
            guard !scored.isEmpty else {
                return ""
            }
            
            let sorted = scored.sorted {
                $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.timestamp > $1.0.timestamp
            }
            
            let results = sorted.map {
                $0.0.content!.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            return results.joined(separator: "\n\n")
            
        } catch {
            return ""
        }
    }
    
    // MARK: - 系统消息生成
    private func getVisionSystemMessage(
        modelDisplayName: String,
        modelInfo: AllModels,
        query: String
    ) -> String {
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        let isZh = currentLanguage.hasPrefix("zh")
        
        // 当前时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = dateFormatter.string(from: Date())
        
        let weekFormatter = DateFormatter()
        weekFormatter.locale = Locale(identifier: currentLanguage)
        weekFormatter.dateFormat = "EEEE"
        let weekDay = weekFormatter.string(from: Date())
        
        // 模块 1：身份设定
        let identitySection: String = {
            if modelInfo.identity == "model" {
                return isZh
                    ? "# 你是视觉助手【\(modelDisplayName)】，正在帮助用户分析图片内容。"
                    : "# You are a vision assistant [\(modelDisplayName)], helping users analyze image content."
            } else {
                let config = modelInfo.characterDesign?.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasConfig = config != nil && !(config!.isEmpty)
                
                if isZh {
                    return hasConfig
                    ? """
                    # 你是视觉助手【\(modelDisplayName)】。
                    你被设定为：
                    \(config!)
                    请记住你的设定，在回复时保证始终遵循这个设定。
                    """
                    : """
                    # 你是视觉助手【\(modelDisplayName)】。
                    请在回复中保持身份一致性与角色风格。
                    """
                } else {
                    return hasConfig
                    ? """
                    # You are a vision assistant [\(modelDisplayName)].
                    You have been configured as:
                    \(config!)
                    Please remember your configuration and always adhere to it when replying.
                    """
                    : """
                    # You are a vision assistant [\(modelDisplayName)].
                    Please maintain consistency in your identity and tone when responding.
                    """
                }
            }
        }()
        
        // 模块 2：时间信息
        let timeSection = isZh
            ? "# 当前时间：\(now)（\(weekDay)）"
            : "# Current Time: \(now) (\(weekDay))"
        
        // 模块 3：用户信息
        var userInfoSection = ""
        if let info = try? context.fetch(FetchDescriptor<UserInfo>()).first {
            var items: [String] = []
            if let name = info.name, !name.isEmpty {
                items.append(isZh ? "- 用户昵称：\(name)" : "- User Nickname: \(name)")
            }
            if let intro = info.userInfo, !intro.isEmpty {
                items.append(isZh ? "- 用户自我介绍：\n\(intro)" : "- User Self-Introduction:\n\(intro)")
            }
            if let requirements = info.userRequirements, !requirements.isEmpty {
                items.append(isZh ? "- 用户对你的要求：\n\(requirements)" : "- User Requests:\n\(requirements)")
            }
            if !items.isEmpty {
                userInfoSection = isZh
                    ? "# 当前用户信息：\n" + items.joined(separator: "\n\n")
                    : "# Current User Information:\n" + items.joined(separator: "\n\n")
            }
        }
        
        // 模块 4：记忆信息
        var memorySection = ""
        if !query.isEmpty {
            let result = retrieveMemory(keyword: query).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !result.isEmpty {
                memorySection = isZh
                ? """
                # 记忆
                在回答用户问题时，请尽量忘记大部分不相关的信息。只有当用户提供的信息与当前问题或对话内容非常相关时，才记住这些信息并加以使用。
                信息：
                \(result)
                """
                : """
                # Memory
                When answering user questions, try to forget most of the unrelated information. Only remember and use the information provided by the user when it is highly relevant to the current question or conversation content.
                Information:
                \(result)
                """
            }
        }
        
        // 汇总所有模块
        let sections = [
            identitySection,
            timeSection,
            userInfoSection,
            memorySection
        ].filter { !$0.isEmpty }
        
        return sections.joined(separator: "\n\n")
    }
    
    // MARK: - 流式请求方法
    func sendPhotoStreamRequest(
        message: [(role: String, image: UIImage?, text: String?)],
        modelDisplayName: String,
        query: String = ""  // 用于记忆检索的关键词
    ) async throws -> AsyncThrowingStream<VisionStreamData, Swift.Error> {
        // 取消当前请求
        if let currentTask = currentTask {
            currentTask.cancel()
            self.currentTask = nil
        }
        
        isCancelled = false
        
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        
        guard let modelInfo = try? context.fetch(
            FetchDescriptor<AllModels>(
                predicate: #Predicate { $0.displayName == modelDisplayName }
            )
        ).first else {
            throw NSError(domain: "DatabaseError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取模型信息"])
        }
        
        guard let apiKey = getAPIKey(for: modelInfo.company ?? "Unknown", context: context) else {
            throw NSError(domain: "APIConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API Key"])
        }
        
        guard let requestURLString = getRequestURL(for: modelInfo.company ?? "Unknown", context: context),
              let requestURL = URL(string: requestURLString), !requestURLString.isEmpty else {
            throw NSError(domain: "URLConfigError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的请求 URL"])
        }
        
        var formattedMessages: [[String: Any]] = []
        
        // 生成系统消息（包含身份设定、用户信息、记忆）
        let systemRole: String = {
            switch modelInfo.company {
            case "OPENAI": return "developer"
            default: return "system"
            }
        }()
        
        let systemMessage = getVisionSystemMessage(
            modelDisplayName: modelDisplayName,
            modelInfo: modelInfo,
            query: query
        )
        
        if !systemMessage.isEmpty {
            formattedMessages.append([
                "role": systemRole,
                "content": systemMessage
            ])
        }
        
        // 视觉分析指引
        let userMessage: String
        if currentLanguage.hasPrefix("zh") {
            userMessage = "解析图片的视觉语义，识别核心需求（例如：场景识别/内容翻译/对象辨认/情感支持/问题解答）并选择置信度最高的一个视角，不要展示选择的过程和理由，直接给出最终的针对该需求的图片分析内容。"
        } else {
            userMessage = "Analyze the visual semantics of the image, identify core needs (e.g., scene recognition/content translation/object identification/emotional support/question answering), and select the perspective with the highest confidence. Do not show the selection process or reasoning; directly provide the final image analysis content addressing that need."
        }

        formattedMessages.append([
            "role": "user",
            "content": userMessage
        ])
        
        // 遍历用户和 AI 过往对话，保持上下文
        for msg in message {
            var messageData: [String: Any] = ["role": msg.role]
            var contentArray: [[String: Any]] = []
            
            // 处理文本
            if let text = msg.text {
                contentArray.append(["type": "text", "text": text])
            }
            
            // 处理图片
            if let image = msg.image {
                guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                    throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析图片数据"])
                }
                let base64String = imageData.base64EncodedString()
                
                var imageUrlValue: [String: Any] = [:]
                switch modelInfo.company?.uppercased() {
                case "ZHIPUAI":
                    imageUrlValue["url"] = base64String
                case "HANLIN":
                    imageUrlValue["url"] = base64String
                case "XAI":
                    imageUrlValue["url"] = "data:image/jpeg;base64,\(base64String)"
                    imageUrlValue["detail"] = "high"
                default:
                    imageUrlValue["url"] = "data:image/jpeg;base64,\(base64String)"
                }
                
                contentArray.append(["type": "image_url", "image_url": imageUrlValue])
            }
            
            // 如果 `contentArray` 为空，则跳过
            if !contentArray.isEmpty {
                messageData["content"] = contentArray
                formattedMessages.append(messageData)
            }
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let baseName = restoreBaseModelName(from: modelInfo.name ?? "Unknown")
        
        let requestBody: [String: Any] = [
            "model": baseName,
            "messages": formattedMessages,
            "stream": true
        ]
        
        // 判断是否需要处理 <think> 标签的模型
        let useThinkTag = (
            (modelInfo.company == "ZHIPUAI" || modelInfo.company == "HANLIN")
            && modelInfo.supportsReasoning
            && (modelInfo.name?.hasPrefix("glm-z1") ?? false)
        )
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        let (result, response) = try await URLSession.shared.bytes(for: request)
        
        guard let response = response as? HTTPURLResponse else {
            throw NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP 响应无效"])
        }
        
        guard 200...299 ~= response.statusCode else {
            let data = try await readErrorBody(from: result)
            let message = parseRequestErrorMessage(from: data)
            let description = message == nil || message?.isEmpty == true
            ? "请求错误（HTTP \(response.statusCode)）"
            : "请求错误（HTTP \(response.statusCode)）：\(message ?? "")"
            throw NSError(domain: "NetworkError", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: description])
        }
        
        let supportsReasoning = modelInfo.supportsReasoning
        
        return AsyncThrowingStream<VisionStreamData, Swift.Error> { continuation in
            Task(priority: .userInitiated) {
                do {
                    // <think> 标签解析状态
                    var inThinkTag = false
                    var thinkBuffer = ""
                    var useThinkTagLocal = useThinkTag
                    
                    for try await line in result.lines {
                        
                        if self.isCancelled {
                            continuation.finish()
                            self.isCancelled = false
                            break
                        }
                        
                        if line.hasPrefix("data: ") {
                            let jsonString = line.replacingOccurrences(of: "data: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            guard let jsonData = jsonString.data(using: .utf8),
                                  let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                                  let choices = jsonObject["choices"] as? [[String: Any]],
                                  let delta = choices.first?["delta"] as? [String: Any] else {
                                continue
                            }
                            
                            var responseData = VisionStreamData()
                            
                            // 处理 reasoning_content 或 reasoning 字段（兼容多种模型）
                            if supportsReasoning {
                                if let reasoningContent = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String {
                                    responseData.reasoning = reasoningContent
                                }
                            }
                            
                            // 处理 content 字段（包括 <think> 标签解析）
                            if var contentText = delta["content"] as? String {
                                if useThinkTagLocal {
                                    // 处理 <think>...</think> 标签
                                    contentText = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    thinkBuffer += contentText
                                    
                                    if !inThinkTag {
                                        if thinkBuffer.contains("<think>") {
                                            inThinkTag = true
                                            let afterOpen = thinkBuffer.components(separatedBy: "<think>").last ?? ""
                                            responseData.reasoning = afterOpen
                                            thinkBuffer = ""
                                        }
                                    } else {
                                        if thinkBuffer.contains("</think>") {
                                            let afterClose = thinkBuffer.components(separatedBy: "</think>").last ?? ""
                                            responseData.content = afterClose
                                            inThinkTag = false
                                            useThinkTagLocal = false  // 结束 think 模式
                                            thinkBuffer = ""
                                        } else {
                                            responseData.reasoning = contentText
                                        }
                                    }
                                } else {
                                    responseData.content = contentText
                                }
                            }
                            
                            // 只有有内容时才 yield
                            if responseData.content != nil || responseData.reasoning != nil {
                                continuation.yield(responseData)
                            }
                            
                            // 检查是否结束
                            if let finishReason = choices.first?["finish_reason"] as? String, !finishReason.isEmpty {
                                break
                            }
                        }
                    }
                    continuation.finish()
                    self.isCancelled = false
                } catch {
                    continuation.finish(throwing: error)
                }
                continuation.onTermination = { @Sendable status in
                    continuation.finish()
                }
            }
        }
    }
}
