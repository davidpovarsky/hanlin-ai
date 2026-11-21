import Foundation
import SwiftUI
import SwiftData
import Observation
import HanlinPresentationKit
import HanlinRichUI
import HanlinHostContracts

/// Lives in the existing ChatView. SwiftData's original rows remain the sole
/// durable owner; rendering a history row never restores tool authority.
@MainActor @Observable
final class HanlinAppRichPresentation {
    @ObservationIgnored private var stores: [PresentationMessageIdentity: MessageOpenUIStateStore] = [:]
    @ObservationIgnored private var descriptor: HostPresentationDescriptor?
    @ObservationIgnored private var pendingSnapshotSaves: [PresentationMessageIdentity: Bool] = [:]
    @ObservationIgnored private var pendingError: String?
    private(set) var error: String?

    func profile(for conversation: ChatRecords, conversationID: UUID) throws -> ResolvedPresentationProfile {
        if descriptor == nil { descriptor = try OpenUICatalogs.host(appID: "hanlin", capabilities: ["original-host-actions"]) }
        guard let descriptor else { throw PresentationResolutionError.profileUnavailable }
        let assignment = try conversation.presentationAssignmentData.map { try JSONDecoder().decode(ConversationPresentationAssignment.self, from: $0) }
        return try ProfileResolver.resolve(host: descriptor, conversationID: conversationID, assignment: assignment)
    }

    func select(_ profileID: String, conversation: ChatRecords, conversationID: UUID, context: ModelContext, temporary: Bool) {
        do {
            let assignment = ConversationPresentationAssignment(conversationID: conversationID, profile: .init(profileID))
            if descriptor == nil { descriptor = try OpenUICatalogs.host(appID: "hanlin", capabilities: ["original-host-actions"]) }
            if let descriptor { _ = try ProfileResolver.resolve(host: descriptor, conversationID: conversationID, assignment: assignment) }
            conversation.presentationAssignmentData = try JSONEncoder().encode(assignment)
            if !temporary { try context.save() }
            pendingError = nil
            if error != nil { error = nil }
        } catch { reportError(error.localizedDescription) }
    }

    func state(for message: ChatMessages, conversation: ChatRecords, conversationID: UUID,
               context: ModelContext, temporary: Bool) -> MessageOpenUIStateStore? {
        let identity = PresentationMessageIdentity(appID: "hanlin", conversationID: conversationID, messageID: message.id)
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

/// Keeps Hanlin's original Markdown view/selection actions. Only marked OpenUI
/// blocks are sent to the embedded renderer, in their exact stream order.
struct HanlinMixedOriginalText<Markdown: View>: View {
    let text: String
    var namespace: String = "answer"
    @ViewBuilder let markdown: (String) -> Markdown
    @Environment(\.hanlinRichMessageContext) private var context

    var body: some View {
        if let context, text.contains("```openui-lang") {
            let parts = OpenUIInlineParts.split(text, identity: context.state.identity,
                catalogs: context.state.profile.profile.catalogIDs, isStreaming: context.isStreaming)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parts) { originalPart in
                    let part = MessageRichPart(id: namespace + "/" + originalPart.id,
                        identity: originalPart.identity, streamOrder: originalPart.streamOrder,
                        catalogVersions: originalPart.catalogVersions, payload: originalPart.payload,
                        isComplete: originalPart.isComplete)
                    switch part.payload {
                    case .markdown(let text): markdown(text)
                    case .openUI:
                        OpenUIBlock(part: part, state: context.state, configuration: .init(nativeComponent: { element, _ in
                            guard ["TextContent", "MarkDownRenderer", "Paragraph"].contains(element.typeName) else { return nil }
                            return AnyView(markdown(element.properties["text"]?.string ?? element.properties["textMarkdown"]?.string ?? ""))
                        }), perform: context.perform)
                    }
                }
            }
        } else { markdown(text) }
    }
}
