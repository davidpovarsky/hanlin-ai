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

// 资源数据结构体
struct Resource: Codable {
    var icon: String
    var title: String
    var link: String
}

// 提示卡片数据结构体
struct PromptCard: Codable, Hashable {
    var name: String
    var content: String
}

// 定位数据结构体
struct Location: Codable, Hashable {
    var id: UUID?
    var identifier: String?
    var name: String
    var latitude: Double
    var longitude: Double
    var style: String
}

// 坐标数据结构体
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
}

// 路线数据结构体
struct RouteInfo: Codable, Hashable {
    var distance: Double               // 路线总距离，单位：米
    var expectedTravelTime: Double     // 预计行驶时间，单位：秒
    var instructions: [String]         // 导航步骤说明
    var routePoints: [Coordinate]      // 路线折线坐标点
}

// 音频数据结构体
struct AudioAsset: Codable, Hashable {
    var data: Data                   // 音频原始数据
    var fileName: String            // 文件名（例如 audio1.m4a）
    var fileType: String            // 格式（例如 m4a、mp3）
    var modelName: String           // 模型名称
    var duration: TimeInterval?     // 可选：时长（秒）
}

// 事件数据结构体
struct EventItem: Codable, Hashable {
    var type: String               // calendar / reminder
    var title: String
    var startDate: Date?           // 仅 calendar 用
    var endDate: Date?             // 仅 calendar 用
    var dueDate: Date?             // 仅 reminder 用
    var location: String?
    var notes: String?
    var priority: Int?             // 仅 reminder 用
    var completed: Bool?           // 仅 reminder 用
    var calendarIdentifier: String?
}

// 健康数据结构体
struct HealthData: Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var proteinGrams: Double?
    var carbohydratesGrams: Double?
    var fatGrams: Double?
    var energyKilocalories: Double?
    var isWritten: Bool? = false   // 写入状态
}

// python代码块
struct CodeBlock: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var codeType: String              // 代码类型
    var code: String                  // 输入的 Python 代码
    var output: String = ""           // 执行后的输出结果
    var isRunning: Bool = false       // 是否正在执行（控制 loading 状态）
    var hasError: Bool = false        // 是否出错（控制红色提示）
    var isExpanded: Bool = true       // 输出区域是否展开
}

struct KnowledgeCard: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var content: String
    var isWritten: Bool? = false
}

@Model
class ChatMessages {
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
        self.modelName = modelName
        self.modelDisplayName = modelDisplayName
        self.groupID = groupID
        self.timestamp = timestamp
        self.record = record
        self.imageArray = images ?? []
        self.routeInfos = routeInfos
    }
}
