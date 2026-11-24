//
//  ChatMessages.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 9/2/25.
//
//

import Foundation
import SwiftData
import PhotosUI
import HanlinPlatformContracts

// 资源数据结构体
public struct Resource: Codable, Sendable {
    public var icon: String
    public var title: String
    public var link: String
}

// 提示卡片数据结构体
public struct PromptCard: Codable, Hashable, Sendable {
    public var name: String
    public var content: String

    public init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

// 定位数据结构体
public struct Location: Codable, Hashable, Sendable {
    public var id: UUID?
    public var identifier: String?
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var style: String
}

// 坐标数据结构体
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
}

// 路线数据结构体
public struct RouteInfo: Codable, Hashable, Sendable {
    public var distance: Double               // 路线总距离，单位：米
    public var expectedTravelTime: Double     // 预计行驶时间，单位：秒
    public var instructions: [String]         // 导航步骤说明
    public var routePoints: [Coordinate]      // 路线折线坐标点
}

// 音频数据结构体
public struct AudioAsset: Codable, Hashable, Sendable {
    public var data: Data                   // 音频原始数据
    public var fileName: String            // 文件名（例如 audio1.m4a）
    public var fileType: String            // 格式（例如 m4a、mp3）
    public var modelName: String           // 模型名称
    public var duration: TimeInterval?     // 可选：时长（秒）
}

// 事件数据结构体
public struct EventItem: Codable, Hashable, Sendable {
    public var type: String               // calendar / reminder
    public var title: String
    public var startDate: Date?           // 仅 calendar 用
    public var endDate: Date?             // 仅 calendar 用
    public var dueDate: Date?             // 仅 reminder 用
    public var location: String?
    public var notes: String?
    public var priority: Int?             // 仅 reminder 用
    public var completed: Bool?           // 仅 reminder 用
    public var calendarIdentifier: String?
}

// 健康数据结构体
public struct HealthData: Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var date: Date
    public var proteinGrams: Double?
    public var carbohydratesGrams: Double?
    public var fatGrams: Double?
    public var energyKilocalories: Double?
    public var isWritten: Bool? = false   // 写入状态
}

// python代码块
public struct CodeBlock: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var codeType: String              // 代码类型
    public var code: String                  // 输入的 Python 代码
    public var output: String = ""           // 执行后的输出结果
    public var isRunning: Bool = false       // 是否正在执行（控制 loading 状态）
    public var hasError: Bool = false        // 是否出错（控制红色提示）
    public var isExpanded: Bool = true       // 输出区域是否展开
}

public struct KnowledgeCard: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var content: String
    public var isWritten: Bool? = false
}

@Model
class ChatMessages {
    /// Optional additive storage keeps old conversations readable. Values are
    /// copied at send time; a later draft cannot mutate a historical selection.
    var capabilityAttachmentsData: Data? = nil

    var capabilityAttachments: [HanlinCapabilityAttachment] {
        (try? decodedCapabilityAttachments()) ?? []
    }

    func decodedCapabilityAttachments() throws -> [HanlinCapabilityAttachment] {
        try capabilityAttachmentsData.map {
            try JSONDecoder().decode([HanlinCapabilityAttachment].self, from: $0)
        } ?? []
    }

    /// Optional presentation state in the original message row; lightweight migration.
    var presentationSnapshotData: Data? = nil
    /// Optional for lightweight migration of existing conversations.
    var modelFinishReason: String? = nil
    var id: UUID = UUID()
    var role: String? = "system"
    var text: String? = nil
    var translatedText: String? = nil
    var images: Data? = nil
    var images_text: String? = nil
    var reasoning: String? = nil
    var reasoningTime: String? = nil
    var reasoningExpanded: Bool? = false
    var toolContent: String? = nil
    var toolName: String? = nil
    var toolContentExpanded: Bool? = false
    var documents: [String]? = nil
    var document_text: String? = nil
    var resources: [Resource]? = nil
    var searchEngine: String? = nil
    var promptUse: [PromptCard]? = nil
    var locationsInfo: [Location]? = nil
    var routeInfoData: Data? = nil
    var mailMessageData: Data? = nil
    var events: [EventItem]? = nil
    var htmlContent: String? = nil
    var healthData: [HealthData]? = nil
    var codeBlockData: [CodeBlock]? = nil
    var knowledgeCard: [KnowledgeCard]? = nil
    var nativeUIBlocksJSON: String? = nil
    var agentRunJSON: String? = nil
    var audioData: Data?
    var audioExpanded: Bool? = false
    var showCanvas: Bool? = false
    var modelName: String? = nil
    var modelDisplayName: String? = nil
    var groupID: UUID = UUID()
    
    var timestamp: Date = Date()
    @Relationship(inverse: \ChatRecords.messages) 
    var record: ChatRecords?

    // 计算属性，将 images 数据转换为 UIImage 数组
    var imageArray: [UIImage] {
        get {
            // 从 images 解码为 UIImage 数组
            guard let data = images else { return [] }
            do {
                let imageDatas = try JSONDecoder().decode([Data].self, from: data)
                return imageDatas.compactMap { UIImage(data: $0) }
            } catch {
                print("Failed to decode images: \(error.localizedDescription)")
                return []
            }
        }
        set {
            // 将 UIImage 数组编码为 Data
            let imageDatas = newValue.compactMap { $0.jpegData(compressionQuality: 0.8) }
            do {
                images = try JSONEncoder().encode(imageDatas)
            } catch {
                print("Failed to encode images: \(error.localizedDescription)")
                images = nil
            }
        }
    }
    
    // 文件地址
    var documentURLs: [URL]? {
        get {
            return documents?.compactMap { URL(string: $0) }
        }
        set {
            documents = newValue?.compactMap { $0.absoluteString }
        }
    }
    
    // 路线计算属性
    var routeInfos: [RouteInfo]? {
        get {
            guard let data = routeInfoData else { return nil }
            return try? JSONDecoder().decode([RouteInfo].self, from: data)
        }
        set {
            routeInfoData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // 音频计算属性
    var audioAssets: [AudioAsset]? {
        get {
            guard let d = audioData else { return nil }
            return try? JSONDecoder().decode([AudioAsset].self, from: d)
        }
        set {
            audioData = try? JSONEncoder().encode(newValue)
        }
    }

    // 初始化方法
    public init(
        id: UUID = UUID(),
        role: String? = "system",
        text: String? = nil,
        translatedText: String? = nil,
        images: [UIImage]? = nil, // 默认值为空数组
        images_text: String? = nil,
        reasoning: String? = nil,
        reasoningTime: String? = nil,
        reasoningExpanded: Bool? = false,
        toolContent: String? = nil,
        toolName: String? = nil,
        toolContentExpanded: Bool? = false,
        documents: [String]? = nil,
        document_text: String? = nil,
        resources: [Resource]? = nil,
        searchEngine: String? = nil,
        promptUse: [PromptCard]? = nil,
        locationsInfo: [Location]? = nil,
        events: [EventItem]? = nil,
        htmlContnt: String? = nil,
        healthData: [HealthData]? = nil,
        codeBlockData: [CodeBlock]? = nil,
        knowledgeCard: [KnowledgeCard]? = nil,
        nativeUIBlocksJSON: String? = nil,
        agentRunJSON: String? = nil,
        modelName: String? = nil,
        modelDisplayName: String? = nil,
        groupID: UUID = UUID(),
        timestamp: Date = Date(),
        record: ChatRecords? = nil,
        routeInfos: [RouteInfo]? = nil,
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.translatedText = translatedText
        self.reasoning = reasoning
        self.reasoningTime = reasoningTime
        self.reasoningExpanded = reasoningExpanded
        self.toolContent = toolContent
        self.toolName = toolName
        self.toolContentExpanded = toolContentExpanded
        self.documents = documents
        self.resources = resources
        self.searchEngine = searchEngine
        self.promptUse = promptUse
        self.locationsInfo = locationsInfo
        self.events = events
        self.htmlContent = htmlContnt
        self.healthData = healthData
        self.codeBlockData = codeBlockData
        self.knowledgeCard = knowledgeCard
        self.nativeUIBlocksJSON = nativeUIBlocksJSON
        self.agentRunJSON = agentRunJSON
        self.modelName = modelName
        self.modelDisplayName = modelDisplayName
        self.groupID = groupID
        self.timestamp = timestamp
        self.record = record
        self.imageArray = images ?? []
        self.routeInfos = routeInfos
    }
}
