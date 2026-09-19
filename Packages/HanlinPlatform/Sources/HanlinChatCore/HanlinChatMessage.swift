// HanlinChatMessage.swift
// HanlinChatCore
//
// Extension-safe message data model for Hanlin chat communication.

import Foundation

public struct HanlinChatMessage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let role: String // "user", "assistant", "system", "search"
    public var content: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    public static func user(_ content: String) -> HanlinChatMessage {
        HanlinChatMessage(role: "user", content: content)
    }

    public static func assistant(_ content: String) -> HanlinChatMessage {
        HanlinChatMessage(role: "assistant", content: content)
    }

    public static func system(_ content: String) -> HanlinChatMessage {
        HanlinChatMessage(role: "system", content: content)
    }
}
