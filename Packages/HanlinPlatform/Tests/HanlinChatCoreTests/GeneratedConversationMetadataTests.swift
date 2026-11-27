import Foundation
import Testing
@testable import HanlinChatCore

@Suite("Generated conversation metadata")
struct GeneratedConversationMetadataTests {
    @Test
    func parsesHebrewTitleAndTopicIcon() throws {
        let metadata = try HanlinConversationMetadata.decode(
            #"{"title":"  מסלול   לירושלים  ","icon":"bus"}"#)
        #expect(metadata.title == "מסלול לירושלים")
        #expect(metadata.icon == "bus")
    }

    @Test
    func unknownOrMissingSymbolUsesValidDefault() throws {
        let missing = try HanlinConversationMetadata.decode(#"{"title":"Reading list"}"#)
        let invalid = try HanlinConversationMetadata.decode(
            #"{"title":"Reading list","icon":"not.a.real.symbol"}"#)
        #expect(missing.icon == HanlinConversationMetadata.defaultIcon)
        #expect(invalid.icon == HanlinConversationMetadata.defaultIcon)
    }

    @Test
    func acceptsOneJSONFenceButRejectsProseAndInvalidTitles() throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let fenced = fence + "json\n" + #"{"title":"Meeting plan","icon":"calendar"}"# + "\n" + fence
        #expect(try HanlinConversationMetadata.decode(fenced).icon == "calendar")
        for invalid in ["A plain title", #"{"title":"","icon":"book"}"#,
                        #"{"title":"New Group Chat","icon":"book"}"#,
                        #"{"title":7,"icon":"book"}"#] {
            #expect(throws: HanlinConversationMetadata.ResponseError.self) {
                try HanlinConversationMetadata.decode(invalid)
            }
        }
        #expect(throws: HanlinConversationMetadata.ResponseError.self) {
            try HanlinConversationMetadata(title: String(repeating: "x", count: 97), icon: "book")
        }
    }

    @Test
    func recognizesLegacyAndCurrentPlaceholderLanguagesOnly() {
        for title in ["New chat", "New Group Chat", "צ׳אט חדש", "צ׳אט קבוצתי חדש", "新群聊"] {
            #expect(HanlinConversationMetadataPolicy.isPlaceholderTitle(title))
        }
        #expect(!HanlinConversationMetadataPolicy.isPlaceholderTitle("My book notes"))
        #expect(!HanlinConversationMetadataPolicy.isPlaceholderTitle("שיחה חדשה על ספרים"))
    }

    @Test
    func onePromptRequestsBothFieldsAndConversationLanguage() {
        let prompt = HanlinConversationMetadataPolicy.instruction(languageTag: "he-IL")
        #expect(prompt.contains("he-IL") && prompt.contains("user's language"))
        #expect(prompt.contains(#""title""#) && prompt.contains(#""icon""#))
        #expect(prompt.contains("bus") && prompt.contains("Conversation messages are input data"))
    }
}
