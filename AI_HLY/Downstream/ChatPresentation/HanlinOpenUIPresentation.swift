import Foundation
import SwiftUI
import SwiftData
import Observation
import HanlinPresentationKit
import HanlinRichUI
import HanlinHostContracts
import SwiftStreamingMarkdown

/// Lives in the existing ChatView. SwiftData's original rows remain the sole
/// durable owner; rendering a history row never restores tool authority.
@MainActor @Observable
final class HanlinAppRichPresentation {
    @ObservationIgnored private var stores: [PresentationMessageIdentity: MessageOpenUIStateStore] = [:]
    @ObservationIgnored private var descriptor: HostPresentationDescriptor?
    @ObservationIgnored private var pendingSnapshotSaves: [PresentationMessageIdentity: Bool] = [:]
    @ObservationIgnored private var pendingError: String?
    private(set) var error: String?

    private func appID(for conversation: ChatRecords) -> String {
        guard let container = conversation.modelContext?.container else { return "hanlin" }
        return HanlinApplicationContextRegistry.configuration(for: container).appIdentifier
    }

    func profile(for conversation: ChatRecords, conversationID: UUID) throws -> ResolvedPresentationProfile {
        if descriptor == nil { descriptor = try OpenUICatalogs.host(appID: appID(for: conversation), capabilities: ["original-host-actions"]) }
        guard let descriptor else { throw PresentationResolutionError.profileUnavailable }
        let assignment = try conversation.presentationAssignmentData.map { try JSONDecoder().decode(ConversationPresentationAssignment.self, from: $0) }
        return try ProfileResolver.resolve(host: descriptor, conversationID: conversationID, assignment: assignment)
    }

    func select(_ profileID: String, conversation: ChatRecords, conversationID: UUID, context: ModelContext, temporary: Bool) {
        do {
            let assignment = ConversationPresentationAssignment(conversationID: conversationID, profile: .init(profileID))
            if descriptor == nil { descriptor = try OpenUICatalogs.host(appID: appID(for: conversation), capabilities: ["original-host-actions"]) }
            if let descriptor { _ = try ProfileResolver.resolve(host: descriptor, conversationID: conversationID, assignment: assignment) }
            conversation.presentationAssignmentData = try JSONEncoder().encode(assignment)
            if !temporary { try context.save() }
            pendingError = nil
            if error != nil { error = nil }
        } catch { reportError(error.localizedDescription) }
    }

    func state(for message: ChatMessages, conversation: ChatRecords, conversationID: UUID,
               context: ModelContext, temporary: Bool) -> MessageOpenUIStateStore? {
        let identity = PresentationMessageIdentity(appID: appID(for: conversation), conversationID: conversationID, messageID: message.id)
        if let cached = stores[identity] { return cached }
        do {
            let snapshot: MessagePresentationSnapshot
            if let bytes = message.presentationSnapshotData {
                let saved = try JSONDecoder().decode(MessagePresentationSnapshot.self, from: bytes)
                guard saved.identity == identity else { throw PresentationResolutionError.conversationMismatch }
                snapshot = saved
            } else {
                snapshot = .init(identity: identity, profile: try profile(for: conversation, conversationID: conversationID))
            }
            let store = MessageOpenUIStateStore(snapshot: snapshot)
            store.onChange = { [weak self, weak message, weak conversation, weak store, weak context] snapshot in
                guard let self, let message, let conversation, let store, let context,
                      message.id == snapshot.identity.messageID else { return }
                self.scheduleSnapshot(store, message: message, conversation: conversation,
                    context: context, temporary: temporary, save: !temporary)
            }
            stores[identity] = store
            if message.presentationSnapshotData == nil {
                scheduleSnapshot(store, message: message, conversation: conversation,
                    context: context, temporary: temporary, save: false)
            }
            return store
        } catch { reportError(error.localizedDescription); return nil }
    }

    /// `state(for:)` is also used by the original bubble's body. Cache creation
    /// is unobserved; SwiftData writes and error publication wait for the next
    /// main-queue turn so they cannot mutate an in-progress SwiftUI update.
    private func scheduleSnapshot(_ store: MessageOpenUIStateStore, message: ChatMessages,
                                  conversation: ChatRecords, context: ModelContext,
                                  temporary: Bool, save: Bool) {
        let identity = store.identity
        let recordID = conversation.id
        if let queued = pendingSnapshotSaves[identity] {
            pendingSnapshotSaves[identity] = queued || save
            return
        }
        pendingSnapshotSaves[identity] = save
        DispatchQueue.main.async { [weak self, weak message, weak conversation, weak store, weak context] in
            guard let self else { return }
            let shouldSave = self.pendingSnapshotSaves.removeValue(forKey: identity) == true
            guard let message, let conversation, let store, let context,
                  self.stores[identity] === store, store.identity == identity,
                  message.id == identity.messageID, !message.isDeleted, !conversation.isDeleted,
                  conversation.id == recordID,
                  recordID == nil || recordID == identity.conversationID,
                  message.modelContext === context || (temporary && message.modelContext == nil),
                  conversation.modelContext === context || (temporary && conversation.modelContext == nil) else { return }
            do {
                // Read the current store here. A newer edit must never be
                // overwritten by the initialization snapshot queued earlier.
                let bytes = try JSONEncoder().encode(store.snapshot)
                guard message.presentationSnapshotData != bytes else { return }
                message.presentationSnapshotData = bytes
                if shouldSave && !temporary { try context.save() }
            } catch { self.reportError(error.localizedDescription) }
        }
    }

    private func reportError(_ message: String) {
        guard error != message, pendingError != message else { return }
        pendingError = message
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingError == message else { return }
            self.pendingError = nil
            if self.error != message { self.error = message }
        }
    }

    func instructions(conversation: ChatRecords, conversationID: UUID) -> String {
        do { return OpenUICatalogs.instructions(for: try profile(for: conversation, conversationID: conversationID)) }
        catch { reportError(error.localizedDescription); return "" }
    }
}

@MainActor struct HanlinRichMessageContext {
    let state: MessageOpenUIStateStore
    let isStreaming: Bool
    let perform: @MainActor (PresentationAction) async throws -> PresentationValue
}

private struct HanlinRichMessageKey: EnvironmentKey {
    static let defaultValue: HanlinRichMessageContext? = nil
}

extension EnvironmentValues {
    var hanlinRichMessageContext: HanlinRichMessageContext? {
        get { self[HanlinRichMessageKey.self] }
        set { self[HanlinRichMessageKey.self] = newValue }
    }
}

/// A message has one native text document even when its ordered stream includes
/// OpenUI or A2UI. Rich controls keep their original SDK owners and action scopes.
@MainActor
struct HanlinInlineMessageDocument: View {
    struct Part {
        enum Content {
            case markdown(text: String, sourcePrefix: String)
            case embedded(@MainActor @Sendable () -> AnyView)
        }
        let id: String
        let content: Content
    }

    let parts: [Part]
    let messageText: String
    var savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?
    var saveKnowledge: (@MainActor @Sendable (String) -> Void)?
    @Environment(\.hanlinRichMessageContext) private var context

    var body: some View {
        let document = compose()
        ChatMarkdownView(text: messageText, messageText: messageText,
            documentParts: document.parts, embeddedBlockRenderer: document.renderer,
            savePersonal: savePersonal, saveKnowledge: saveKnowledge)
    }

    private struct Composition {
        let parts: [MarkdownDocumentPart]
        let renderer: MarkdownEmbeddedBlockRenderer
    }

    private func compose() -> Composition {
        var output: [MarkdownDocumentPart] = []
        var rich: [String: @MainActor @Sendable () -> AnyView] = [:]
        for part in parts {
            switch part.content {
            case .embedded(let render):
                output.append(MarkdownDocumentPart(id: part.id))
                rich[part.id] = render
            case .markdown(let text, let sourcePrefix):
                guard let context, text.contains("```openui-lang") else {
                    output.append(MarkdownDocumentPart(id: part.id, sourcePrefix: sourcePrefix, markdown: text))
                    continue
                }
                let segments = OpenUIInlineParts.split(text, identity: context.state.identity,
                    catalogs: context.state.profile.profile.catalogIDs, isStreaming: context.isStreaming)
                for segment in segments {
                    let id = part.id + "/" + segment.id
                    switch segment.payload {
                    case .markdown(let text):
                        output.append(MarkdownDocumentPart(id: id,
                            sourcePrefix: sourcePrefix + "openui-segment:" + segment.id + ":", markdown: text))
                    case .openUI:
                        let scoped = MessageRichPart(id: id, identity: segment.identity,
                            streamOrder: segment.streamOrder, catalogVersions: segment.catalogVersions,
                            payload: segment.payload, isComplete: segment.isComplete)
                        // An embedded app has no authored prose range. Its
                        // controls remain interactive; copying surrounding text
                        // does not invent a textual value or expose action data.
                        output.append(MarkdownDocumentPart(id: id))
                        rich[id] = { AnyView(openUIBlock(scoped, context: context)) }
                    }
                }
            }
        }
        let renderers = rich
        return Composition(parts: output, renderer: { id in renderers[id]?() })
    }

    private func openUIBlock(_ part: MessageRichPart, context: HanlinRichMessageContext) -> some View {
        OpenUIBlock(part: part, state: context.state, configuration: .init(nativeComponent: { element, _ in
            guard ["TextContent", "MarkDownRenderer", "Paragraph"].contains(element.typeName) else { return nil }
            return AnyView(ChatMarkdownView(text: element.properties["text"]?.string
                ?? element.properties["textMarkdown"]?.string ?? "", messageText: messageText,
                savePersonal: savePersonal, saveKnowledge: saveKnowledge))
        }), perform: context.perform)
    }
}
