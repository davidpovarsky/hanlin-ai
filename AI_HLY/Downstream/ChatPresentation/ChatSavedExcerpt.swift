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
    var renderedText: String?
    var renderedLocation: Int?
    var renderedLength: Int?
    var sourceBlockID: String?
    var utf16Location: Int?
    var utf16Length: Int?

    init(source: ChatExcerptSource, markdown: String, quote: String, selection: ChatTextQuote? = nil) {
        renderedText = selection?.renderedText
        renderedLocation = selection?.range.location
        renderedLength = selection?.range.length
        sourceBlockID = selection?.sourceBlockID
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
    static func save(source: ChatExcerptSource, markdown: String, quote: String, selection: ChatTextQuote? = nil, in context: ModelContext) throws -> ChatSavedExcerpt {
        let chatID = source.chatRecordID
        let messageID = source.messageID
        let digest = digest(markdown)
        let candidates = try context.fetch(FetchDescriptor<ChatSavedExcerpt>(predicate: #Predicate {
            $0.chatRecordID == chatID && $0.messageID == messageID && $0.sourceDigest == digest && $0.quote == quote
        }))
        if let existing = candidates.first(where: {
            $0.sourceBlockID == selection?.sourceBlockID && $0.renderedLocation == selection?.range.location
                && $0.renderedLength == selection?.range.length && $0.renderedText == selection?.renderedText
        }) { return existing }
        let excerpt = ChatSavedExcerpt(source: source, markdown: markdown, quote: quote, selection: selection)
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
    @Entry var chatSourceDestination: ChatSourceDestination? = nil
    @Entry var chatOpenSavedSource: (@MainActor (ChatRecords, ChatSourceDestination) -> Void)? = nil
    @Entry var chatMarkdownSelectionActivity: (@MainActor @Sendable (UUID, Bool) -> Void)? = nil
    @Entry var chatMarkdownDidRender: (@MainActor @Sendable (UUID) -> Void)? = nil
}

/// Rendered offsets are never confused with Markdown-source offsets.
struct ChatTextQuote: Sendable, Equatable {
    let text: String
    let renderedText: String
    let range: NSRange
    let sourceBlockID: String?
}

struct ChatSourceDestination: Sendable, Equatable, Identifiable {
    let id = UUID()
    let chatRecordID: UUID
    let messageID: UUID
    let quote: String
    let sourceDigest: String
    let selection: ChatTextQuote?

    init?(excerpt: ChatSavedExcerpt) {
        guard let chatID = excerpt.chatRecordID, let messageID = excerpt.messageID else { return nil }
        self.chatRecordID = chatID
        self.messageID = messageID
        quote = excerpt.quote
        sourceDigest = excerpt.sourceDigest
        if let rendered = excerpt.renderedText, let location = excerpt.renderedLocation,
           let length = excerpt.renderedLength {
            selection = ChatTextQuote(text: excerpt.quote, renderedText: rendered,
                range: NSRange(location: location, length: length), sourceBlockID: excerpt.sourceBlockID)
        } else { selection = nil }
    }
}
