import Foundation
import SwiftData

/// The original ChatView's stream-to-row projection, shared by the mounted UI
/// and the headless application controller. It retains the existing rows,
/// coordinator, search/split behavior and every rich payload representation.
@MainActor
final class HanlinConversationStreamProjection {
    let chatRecord: ChatRecords
    let context: ModelContext
    let groupBeginMessage: ChatMessages
    let agentCoordinator: AgentRunCoordinator
    private let lease: HanlinConversationRunLease?
    var messages: [ChatMessages]
    var assistantMessage: ChatMessages
    var searchMessage: ChatMessages?
    var isSearch = false
    var operationalState = ""
    var operationalDescription = ""
    private var eventAdapter: HanlinStreamEventAdapter
    private var agentProjection: ClassicChatAgentProjection
    private var warningKinds = Set<String>()
    private var reasoningStart: Date?
    private var reasoningEnd: Date?
    private var reasoningTotal: Double?
    private let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
    private(set) var completionStatus = "completed"

    init(record: ChatRecords, context: ModelContext, messages: [ChatMessages],
         assistant: ChatMessages, coordinator: AgentRunCoordinator, lease: HanlinConversationRunLease? = nil) {
        self.lease = lease
        chatRecord = record
        self.context = context
        self.messages = messages
        assistantMessage = assistant
        groupBeginMessage = assistant
        agentCoordinator = coordinator
        eventAdapter = HanlinStreamEventAdapter(runID: coordinator.runID)
        agentProjection = ClassicChatAgentProjection(runID: coordinator.runID)
    }

    func consume(_ data: StreamData, hasCanonicalParts: Bool = false) {
        let rawAgentEvents = eventAdapter.events(from: data)

        let agentEvents = agentProjection.deduplicateEvents(rawAgentEvents)
        agentCoordinator.consume(agentEvents)

        var updated = false

        // 普通回复文本
        if let content = data.content {
            if hasCanonicalParts { assistantMessage = groupBeginMessage }
            assistantMessage.text?.append(content)
            if !operationalState.isEmpty { operationalState = "" }
            if let start = reasoningStart, let end = reasoningEnd {
                let seg = end.timeIntervalSince(start)
                reasoningTotal = (reasoningTotal ?? 0) + seg
            }
            reasoningStart = nil
            reasoningEnd   = nil
            updated = true
        }

        // 推理文本
        if let reasoning = data.reasoning {
            let now = Date()
            if reasoningStart == nil { reasoningStart = now }
            reasoningEnd = now

            // 初始化一下，防止 nil
            if groupBeginMessage.reasoning == nil {
                groupBeginMessage.reasoning = ""
            }
            let cleanedReasoning = ClassicChatAgentProjection.stripRawThinkTags(reasoning)
            if !cleanedReasoning.isEmpty {
                groupBeginMessage.reasoning! += cleanedReasoning
            }

            if !operationalState.isEmpty { operationalState = "" }
            updated = true
        }

        // 工具文本、资源、NativeUIBlocks 与 AgentRun 同步投影
        if agentProjection.applyStreamChunk(
            data,
            agentRun: agentCoordinator.run,
            to: assistantMessage,
            operationalState: &operationalState,
            operationalDescription: &operationalDescription
        ) {
            updated = true
        }

        // 搜索引擎信息
        if let searchEngine = data.searchEngine {
            assistantMessage.searchEngine = searchEngine
            searchMessage?.searchEngine = searchEngine
            updated = true
        }

        // 图像内容
        if let imageContent = data.image_content, !imageContent.isEmpty {
            assistantMessage.imageArray = imageContent
            if !operationalState.isEmpty { operationalState = "" }
            if let start = reasoningStart, let end = reasoningEnd {
                let seg = end.timeIntervalSince(start)
                reasoningTotal = (reasoningTotal ?? 0) + seg
            }
            reasoningStart = nil
            reasoningEnd = nil
            updated = true
        }

        // 图像描述文本
        if let imageText = data.image_text, !imageText.isEmpty {
            if let index = messages.lastIndex(where: { !$0.imageArray.isEmpty && ($0.images_text?.isEmpty ?? true) }),
               index < messages.count {
                messages[index].images_text = imageText
                updated = true
            }
        }

        // 文件内容文本
        if let documentText = data.document_text, !documentText.isEmpty {
            if let index = messages.lastIndex(where: { $0.documents != nil && ($0.document_text?.isEmpty ?? true) }),
               index < messages.count {
                messages[index].document_text = documentText
                updated = true
            }
        }

        // 搜索返回文本
        if let searchText = data.search_text, !searchText.isEmpty {
            let newSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            searchMessage = ChatTurnStateOperations.upsertSearchMessage(
                existing: searchMessage,
                text: newSearchText,
                searchEngine: data.searchEngine ?? assistantMessage.searchEngine,
                assistantMessage: assistantMessage,
                record: chatRecord,
                in: &messages
            )
            isSearch = true
            updated = true
        }

        // 位置信息
        if let locationsInfo = data.locations_info, !locationsInfo.isEmpty {
            assistantMessage.locationsInfo = locationsInfo
            updated = true
        }

        // 路线信息
        if let routeInfo = data.route_info, !routeInfo.isEmpty {
            assistantMessage.routeInfos = routeInfo
            updated = true
        }

        // 事件信息
        if let eventsInfo = data.events, !eventsInfo.isEmpty {
            assistantMessage.events = eventsInfo
            updated = true
        }

        // 网页信息
        if let htmlContent = data.htmlContent, !htmlContent.isEmpty {
            assistantMessage.htmlContent = htmlContent
            updated = true
        }

        // 健康信息
        if let healthCard = data.health_info, !healthCard.isEmpty {
            assistantMessage.healthData = healthCard
            updated = true
        }

        // 代码信息
        if let codeBlock = data.code_info, !codeBlock.isEmpty {
            assistantMessage.codeBlockData = codeBlock
            updated = true
        }

        // 知识卡片
        if let knowledgeCard = data.knowledge_card, !knowledgeCard.isEmpty {
            assistantMessage.knowledgeCard = knowledgeCard
            updated = true
        }

        // 画布信息
        if let canvasInfo = data.canvas_info {
            do {
                // 调用保存接口，将未保存的 canvasInfo 持久化到 chatRecord
                _ = try CanvasServices.saveCanvas(
                    canvasInfo,
                    to: chatRecord,
                    in: context
                )
                assistantMessage.showCanvas = true
                updated = true
            } catch {
                // 保存失败时的处理
                print("保存画布失败：\(error)")
                // 可根据需要弹 alert 或者设置一个 error 状态供 UI 展示
            }
        }

        // 语音信息
        if let asset = data.audioAsset {
            assistantMessage.audioAssets = [asset]
            assistantMessage.audioExpanded = true
            updated = true
        }

        // 更新信息
        if updated {
            if let start = reasoningStart, let end = reasoningEnd {
                let closed = reasoningTotal ?? 0
                let openSeg = end.timeIntervalSince(start)
                let totalSeconds = closed + openSeg

                let text: String
                if currentLanguage.hasPrefix("zh") {
                    if totalSeconds < 60 {
                        text = String(format: "已思考%.1f秒", totalSeconds)
                    } else if totalSeconds < 3600 {
                        let minutes = Int(totalSeconds) / 60
                        let seconds = totalSeconds - Double(minutes * 60)
                        text = String(format: "已思考%d分钟%.1f秒", minutes, seconds)
                    } else {
                        // 支持小时
                        let hours = Int(totalSeconds) / 3600
                        let remainder = Int(totalSeconds) % 3600
                        let minutes = remainder / 60
                        let seconds = Double(remainder % 60)
                        text = String(format: "已思考%d小时%d分钟%.1f秒", hours, minutes, seconds)
                    }
                } else {
                    if totalSeconds < 60 {
                        text = String(format: "Thought for %.1f sec", totalSeconds)
                    } else if totalSeconds < 3600 {
                        let minutes = Int(totalSeconds) / 60
                        let seconds = totalSeconds - Double(minutes * 60)
                        text = String(format: "Thought for %d min %.1f sec", minutes, seconds)
                    } else {
                        // 支持小时
                        let hours = Int(totalSeconds) / 3600
                        let remainder = Int(totalSeconds) % 3600
                        let minutes = remainder / 60
                        let seconds = Double(remainder % 60)
                        text = String(format: "Thought for %d hr %d min %.1f sec", hours, minutes, seconds)
                    }
                }
                if text != groupBeginMessage.reasoningTime, !text.isEmpty {
                    groupBeginMessage.reasoningTime = text
                }
            }
        }

        if let split = data.splitMarkers {
            assistantMessage.reasoning = assistantMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(assistantMessage)
            // 创建助手消息占位符，并保存引用以便后续高效更新
            let newPlaceholder = ChatMessages(
                role: "assistant",
                text: "",
                images: nil,
                reasoning: "",
                documents: nil,
                modelName: split.modelName,
                modelDisplayName: split.modelDisplayName,
                groupID: split.groupID,
                timestamp: Date(),
                record: chatRecord
            )
            messages.append(newPlaceholder)
            assistantMessage = newPlaceholder
        }

        // 异常提醒
        if let error = data.errorInfo, !error.isEmpty, warningKinds.insert(error).inserted {
            if error == "length" { assistantMessage.modelFinishReason = "length" }
            var errorMessage = ""
            if error == "length" {
                errorMessage = String(localized: "The answer reached the configured output limit. The partial answer is saved. Choose Continue to keep going.")
            } else if error == "sensitive" {
                errorMessage = currentLanguage.hasPrefix("zh") ? "⚠️ 包含敏感内容！" : "⚠️ Contains sensitive content!"
            } else {
                errorMessage = error
            }
            if !errorMessage.isEmpty {
                let infoMessage = ChatMessages(
                    role: "information",
                    text: errorMessage,
                    images: [],
                    reasoning: "",
                    documents: nil,
                    modelName: "system",
                    modelDisplayName: "system",
                    timestamp: Date(),
                    record: chatRecord
                )

                messages.append(infoMessage)
            }
        }
    }

    /// Original completion projection. UI-only feedback and scrolling remain
    /// with the caller; every persisted payload is finalized here once.
    func finish(hasCanonicalParts: Bool = false, hasStructuredContent: Bool = false) throws {
        defer { lease?.release() }
        agentCoordinator.consume(eventAdapter.completionEvents())
        var completionSeenBlocks = Set<String>()
        ClassicChatAgentProjection.syncAgentRunProjection(agentCoordinator.run,
            into: assistantMessage, seenToolContentBlocks: &completionSeenBlocks)
        guard messages.contains(where: { $0 === assistantMessage }) else { return }
        if hasCanonicalParts { assistantMessage = groupBeginMessage }
        var textContent = assistantMessage.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hasCanonicalParts, textContent.isEmpty,
           let recoveredAnswer = AgentTranscriptValidation.finalAnswer(in: agentCoordinator.run.transcriptItems)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !recoveredAnswer.isEmpty {
            textContent = recoveredAnswer
            assistantMessage.text = recoveredAnswer
        }
        let reasoningContent = assistantMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if hasCanonicalParts { textContent = assistantMessage.text ?? "" }
        let hasRichContent = hasStructuredContent || !assistantMessage.imageArray.isEmpty
            || assistantMessage.codeBlockData?.isEmpty == false
            || assistantMessage.knowledgeCard?.isEmpty == false
            || assistantMessage.htmlContent?.isEmpty == false
            || assistantMessage.events?.isEmpty == false
            || assistantMessage.healthData?.isEmpty == false
            || assistantMessage.locationsInfo?.isEmpty == false
            || assistantMessage.routeInfos?.isEmpty == false
            || assistantMessage.audioAssets?.isEmpty == false
            || assistantMessage.nativeUIBlocks.isEmpty == false
            || assistantMessage.showCanvas == true
            || agentCoordinator.run.transcriptItems.contains(where: { $0.kind == .userVisibleToolResult })
        operationalState = ""
        operationalDescription = ""
        if textContent.isEmpty && reasoningContent.isEmpty && !hasRichContent {
            completionStatus = "failed"
            agentCoordinator.fail(AgentSafeError(message: String(localized: "⚠️ 生成内容为空，请重新尝试！")))
            groupBeginMessage.agentRun = agentCoordinator.run
            assistantMessage.text = currentLanguage.hasPrefix("zh")
                ? "⚠️ 生成内容为空，请重新尝试！" : "⚠️ Generated content is empty, please try again!"
            assistantMessage.role = "error"
            assistantMessage.modelName = "system"
            assistantMessage.modelDisplayName = "system"
            context.insert(groupBeginMessage)
            try context.save()
            return
        }
        completionStatus = "completed"
        agentCoordinator.complete()
        groupBeginMessage.agentRun = agentCoordinator.run
        assistantMessage.text = textContent
        assistantMessage.reasoning = assistantMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSearch, let searchMessage {
            searchMessage.record = chatRecord
            context.insert(searchMessage)
        }
        context.insert(assistantMessage)
        if let outputText = assistantMessage.text?.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines), !outputText.isEmpty {
            chatRecord.infoDescription = "\(outputText.prefix(80))"
            chatRecord.lastEdited = assistantMessage.timestamp
        } else if !assistantMessage.imageArray.isEmpty {
            if messages.count >= 2, let previous = messages[safe: messages.count - 2] {
                let preview = previous.text?.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines).prefix(80) ?? ""
                chatRecord.infoDescription = "[\(String(localized: "Image"))] \(preview)"
                chatRecord.lastEdited = previous.timestamp
            } else {
                chatRecord.infoDescription = "[\(String(localized: "Image"))]"
                chatRecord.lastEdited = assistantMessage.timestamp
            }
        }
        try context.save()
    }

    func appendPersistenceError(_ error: Error) {
        let text = currentLanguage.hasPrefix("zh")
            ? "⚠️ 数据同步失败: \(error.localizedDescription)，本轮问答不会被同步。"
            : "⚠️ Data synchronization failed: \(error.localizedDescription). This round of Q&A will not be synchronized."
        messages.append(ChatMessages(role: "information", text: text,
            modelDisplayName: "system", timestamp: Date(), record: chatRecord))
        operationalState = ""
        operationalDescription = ""
    }

    func fail(_ error: Error) {
        defer { lease?.release() }
        completionStatus = "failed"
        agentCoordinator.fail(error)
        groupBeginMessage.agentRun = agentCoordinator.run
        if let row = messages.last(where: { $0.role == "assistant" }) {
            row.text = "⚠️ " + String(format: String(localized: "Response error: %@"), error.localizedDescription)
            row.role = "error"
            row.modelDisplayName = "system"
        }
        operationalState = ""
        operationalDescription = ""
        context.insert(groupBeginMessage)
        // Persist the original error projection in the same save as the failed
        // run status; the old view saved before setting the visible error text.
        try? context.save()
    }

    func cancel() {
        defer { lease?.release() }
        completionStatus = "cancelled"
        agentCoordinator.cancel()
        groupBeginMessage.agentRun = agentCoordinator.run
        let hasText = !(groupBeginMessage.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasReasoning = !(groupBeginMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasTool = !(groupBeginMessage.toolContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasImages = !groupBeginMessage.imageArray.isEmpty
        if !hasText && !hasReasoning && !hasTool && !hasImages {
            messages.removeAll { $0 === groupBeginMessage }
        } else {
            context.insert(groupBeginMessage)
        }
        operationalState = ""
        operationalDescription = ""
        Self.appendCancellation(to: &messages, record: chatRecord, context: context)
    }

    static func appendCancellation(to messages: inout [ChatMessages], record: ChatRecords, context: ModelContext) {
        let information = ChatMessages(role: "information",
            text: "🛑 \(String(localized: "Response interrupted"))",
            modelName: "system", modelDisplayName: "system", timestamp: Date(), record: record)
        messages.append(information)
        context.insert(information)
        try? context.save()
    }

    static func requestMessages(from messages: [ChatMessages], limit: Int) -> [RequestMessage] {
        messages.suffix(limit < 0 ? 999 : limit).map { chat in
            RequestMessage(role: chat.role ?? "system", text: chat.text ?? "",
                images: chat.imageArray.isEmpty ? nil : chat.imageArray,
                imageText: chat.images_text ?? "",
                document: chat.documentURLs?.isEmpty == false ? chat.documentURLs : nil,
                documentText: chat.document_text ?? "", htmlContent: chat.htmlContent ?? "",
                prompt: chat.promptUse, modelName: chat.modelName ?? "Unknown",
                modelDisplayName: chat.modelDisplayName ?? "Unknown")
        }
    }
}
