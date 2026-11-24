import HanlinLocalization
import Foundation
import SwiftData
import SwiftUI

/// A route into the original conversation UI. Library callbacks retain their
/// original source-selection provenance, so citations reveal the same passage.
public struct HanlinConversationDestination: Identifiable {
    public let id: UUID
    public let conversationID: UUID
    public let messageID: UUID?
    let source: ChatSourceDestination?

    public init(conversationID: UUID, messageID: UUID? = nil) {
        self.id = UUID()
        self.conversationID = conversationID
        self.messageID = messageID
        self.source = nil
    }

    init(_ selection: HanlinConversationSelection) {
        id = selection.id
        conversationID = selection.conversationID
        messageID = selection.messageID
        source = selection.source
    }
}

/// The original complete ChatView: composer, transcript, reasoning, tool
/// activity, citations, OpenUI/A2UI, attachments, animations and interactions.
/// Place it in the host's navigation/layout and apply ordinary SwiftUI
/// modifiers. It creates no second renderer, engine or conversation store.
@MainActor
public struct HanlinConversationView: View {
    private let context: HanlinApplicationContext
    private let destination: HanlinConversationDestination

    public init(context: HanlinApplicationContext, conversationID: UUID,
                matchedMessageID: UUID? = nil) {
        self.context = context
        self.destination = .init(conversationID: conversationID, messageID: matchedMessageID)
    }

    public init(context: HanlinApplicationContext, destination: HanlinConversationDestination) {
        self.context = context
        self.destination = destination
    }

    public var body: some View {
        HanlinResolvedConversationView(destination: destination)
            .hanlinApplicationContext(context)
    }
}

@MainActor
struct HanlinResolvedConversationView: View {
    let destination: HanlinConversationDestination
    let surface: HanlinConversationSurface
    let externalComposerBottomInset: CGFloat?
    let availableComposerWorkspaceSize: CGSize?
    @Query private var records: [ChatRecords]

    init(destination: HanlinConversationDestination, surface: HanlinConversationSurface = .full,
         externalComposerBottomInset: CGFloat? = nil, availableComposerWorkspaceSize: CGSize? = nil) {
        self.destination = destination
        self.surface = surface
        self.externalComposerBottomInset = externalComposerBottomInset
        self.availableComposerWorkspaceSize = availableComposerWorkspaceSize
        let identifier: UUID? = destination.conversationID
        _records = Query(filter: #Predicate<ChatRecords> { $0.id == identifier })
    }

    var body: some View {
        if records.count == 1, let record = records.first {
            ChatView(chatRecord: record, surface: surface, externalComposerBottomInset: externalComposerBottomInset,
                availableComposerWorkspaceSize: availableComposerWorkspaceSize, matchedMessageID: destination.messageID)
                .environment(\.chatSourceDestination, destination.source)
                .id(destination.conversationID)
        } else {
            ContentUnavailableView(hanlin: "Conversation unavailable", systemImage: "bubble.left",
                description: Text(records.isEmpty
                    ? "This conversation is no longer available in this application context."
                    : "More than one stored conversation has this identifier."))
        }
    }
}
