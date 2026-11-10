import CryptoKit
import Foundation
import SwiftData
import SwiftUI

/// A personal bookmark, deliberately independent of KnowledgeRecords and agent memory.
/// Scalar source IDs keep the snapshot after the original conversation is deleted.
@Model
final class ChatSavedExcerpt {
    var id: UUID = UUID()
    var chatRecordID: UUID?
    var messageID: UUID?
    var groupID: UUID?
    var runID: UUID?
    var createdAt: Date = Date()
    var sourceTitle: String = ""
    var sourceMarkdown: String = ""
    var sourceDigest: String = ""
    var quote: String = ""
    var prefix: String = ""
    var suffix: String = ""
    var utf16Location: Int?
    var utf16Length: Int?

    init(source: ChatExcerptSource, markdown: String, quote: String) {
        chatRecordID = source.chatRecordID
        messageID = source.messageID
        groupID = source.groupID
        runID = source.runID
        sourceTitle = source.title
        sourceMarkdown = markdown
        sourceDigest = Self.digest(markdown)
        self.quote = quote
        // A renderer supplies selected *visible* text, which need not be contiguous Markdown.
        // Store offsets only when the source has one exact match; never invent an ambiguous range.
        if let range = markdown.range(of: quote),
           markdown[range.upperBound...].range(of: quote) == nil {
            let nsRange = NSRange(range, in: markdown)
            utf16Location = nsRange.location
            utf16Length = nsRange.length
            prefix = String(markdown[..<range.lowerBound].suffix(48))
            suffix = String(markdown[range.upperBound...].prefix(48))
        }
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    @discardableResult
    static func save(source: ChatExcerptSource, markdown: String, quote: String, in context: ModelContext) throws -> ChatSavedExcerpt {
        let chatID = source.chatRecordID
        let messageID = source.messageID
        let digest = digest(markdown)
        let candidates = try context.fetch(FetchDescriptor<ChatSavedExcerpt>(predicate: #Predicate {
            $0.chatRecordID == chatID && $0.messageID == messageID && $0.sourceDigest == digest && $0.quote == quote
        }))
        if let existing = candidates.first { return existing }
        let excerpt = ChatSavedExcerpt(source: source, markdown: markdown, quote: quote)
        context.insert(excerpt)
        do { try context.save() }
        catch { context.delete(excerpt); throw error }
        return excerpt
    }
}

struct ChatExcerptSource: Sendable {
    let chatRecordID: UUID?
    let messageID: UUID
    let groupID: UUID?
    let runID: UUID?
    let title: String
}

extension EnvironmentValues {
    @Entry var chatExcerptSource: ChatExcerptSource? = nil
    @Entry var chatHighlightedQuote: String? = nil
}
