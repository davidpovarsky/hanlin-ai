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
            error = nil
        } catch { self.error = error.localizedDescription }
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
                message.presentationSnapshotData = try JSONEncoder().encode(snapshot)
            }
            let store = MessageOpenUIStateStore(snapshot: snapshot)
            store.onChange = { [weak self, weak message] snapshot in
                guard let message, message.id == snapshot.identity.messageID else { return }
                do {
                    message.presentationSnapshotData = try JSONEncoder().encode(snapshot)
                    if !temporary { try context.save() }
                } catch { self?.error = error.localizedDescription }
            }
            stores[identity] = store
            return store
        } catch { self.error = error.localizedDescription; return nil }
    }

    func instructions(conversation: ChatRecords, conversationID: UUID) -> String {
        do { return OpenUICatalogs.instructions(for: try profile(for: conversation, conversationID: conversationID)) }
        catch { self.error = error.localizedDescription; return "" }
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
                    case .openUI: OpenUIBlock(part: part, state: context.state, perform: context.perform)
                    }
                }
            }
        } else { markdown(text) }
    }
}
