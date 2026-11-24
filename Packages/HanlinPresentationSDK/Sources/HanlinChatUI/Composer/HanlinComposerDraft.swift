import Foundation
import Observation
import HanlinPlatformContracts

#if canImport(UIKit)
/// The original Hanlin draft owner shared by the app and independently embedded composers.
/// Text and capability choices belong to this one draft, never to global catalog preferences.
@MainActor
@Observable
public final class HanlinComposerDraft {
    public private(set) var snapshot: NativeMultilineTextEditor.TextState
    public var capabilityAttachments: [HanlinCapabilityAttachment]

    public var text: String {
        get { snapshot.text }
        set {
            snapshot = .init(ownerID: snapshot.ownerID, revision: UUID(), text: newValue)
        }
    }

    /// Value-semantic copy for the outgoing request. Editing this draft later
    /// cannot modify the already submitted configuration.
    public var capabilitySnapshot: [HanlinCapabilityAttachment] { capabilityAttachments }

    public init(text: String = "", capabilityAttachments: [HanlinCapabilityAttachment] = []) {
        snapshot = .init(ownerID: UUID(), revision: UUID(), text: text)
        self.capabilityAttachments = capabilityAttachments
    }

    /// Re-selecting a capability keeps the user's existing configuration.
    @discardableResult
    public func attach(_ attachment: HanlinCapabilityAttachment) -> UUID {
        if let existing = capabilityAttachments.first(where: { $0.selectionKey == attachment.selectionKey }) {
            return existing.id
        }
        capabilityAttachments.append(attachment)
        return attachment.id
    }

    public func removeCapability(id: UUID) {
        capabilityAttachments.removeAll { $0.id == id }
    }

    public func updateCapability(_ attachment: HanlinCapabilityAttachment) {
        guard let index = capabilityAttachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        capabilityAttachments[index] = attachment
        // An action can be changed in the configuration page. Keep that page's
        // identity and latest values while consolidating an existing selection.
        capabilityAttachments.removeAll {
            $0.id != attachment.id && $0.selectionKey == attachment.selectionKey
        }
    }

    public func clearCapabilities() {
        capabilityAttachments.removeAll()
    }
}
#endif
