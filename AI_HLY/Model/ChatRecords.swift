//
//  ChatRecords.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 9/2/25.
//
//

import Foundation
import HanlinChatCore
import SwiftData
import SwiftUI

struct CanvasData: Codable, Hashable {
    var title: String = ""       // 画布标题
    var content: String = ""     // 画布文字
    var type: String = ""        // 画布类型
    var saved: Bool = false      // 是否已经保存
    var id: UUID? = nil          // 画布知识编号
    var history: [String]? = []
    var index: Int? = 0
}

@Model
class ChatRecords {
    var id: UUID? = UUID()
    @Attribute(.spotlight)
    var name: String?
    var type: String?
    var infoDescription: String?
    var lastEdited: Date = Date()
    var isPinned: Bool = false
    var icon: String?                 // 存储图标名称
    var color: String?                // 颜色的名称
    var input: String? = ""           // 正在输入
    var useModel: Int? = -1           // 正在使用的模型
    var temperature: Double = -999    // 采样温度参数（默认 不设置）
    var topP: Double = -999           // 累积概率参数（默认 不设置）
    var maxTokens: Int = HanlinChatGenerationDefaults.maxTokens
    var maxMessagesNum: Int = 20      // 消息数量参数，默认为 20
    var systemMessage: String? = ""   // 系统消息
    var useSystemMessage: Bool = true
    var canvas: CanvasData? = nil     // 画布信息
    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessages]?
    
    // 初始化方法
    public init(
        id: UUID? = UUID(),
        name: String?,
        type: String?,
        description: String? = nil,
        lastEdited: Date = Date(),
        isPinned: Bool = false,
        icon: String = "bubble.left.circle",
        color: String = "hlBlue",
        input: String? = "",            // 正在输入
        useModel: Int? = -1,            // 正在使用的模型
        temperature: Double = -999,     // 采样温度参数（默认 不设置）
        topP: Double = -999,            // 累积概率参数（默认 不设置）
        maxTokens: Int = HanlinChatGenerationDefaults.maxTokens,
        maxMessagesNum: Int = 20,       // 消息数量参数，默认为 20
        systemMessage: String? = "",
        useSystemMessage: Bool = true,
        canvas: CanvasData? = nil,
        messages: [ChatMessages]? = nil,
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.infoDescription = description
        self.lastEdited = lastEdited
        self.isPinned = isPinned
        self.icon = icon
        self.color = color
        self.input = input
        self.useModel = useModel
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.maxMessagesNum = maxMessagesNum
        self.systemMessage = systemMessage
        self.useSystemMessage = useSystemMessage
        self.canvas = canvas
        self.messages = messages
    }
}
