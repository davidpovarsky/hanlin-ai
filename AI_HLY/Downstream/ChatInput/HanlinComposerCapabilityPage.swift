import SwiftUI
import HanlinChatUI
import HanlinLocalization
import HanlinPlatformContracts

/// Content only: the existing Morph bubble owns navigation, glass and scrolling.
struct HanlinComposerCapabilityPage: View {
    let draft: HanlinComposerDraft?
    let capabilities: [HanlinComposerCapabilityDescriptor]
    @Binding var editingAttachmentID: UUID?
    let onAttach: (HanlinComposerCapabilityDescriptor, String?) -> Void

    var body: some View {
        if let draft, let id = editingAttachmentID,
           let attachment = draft.capabilityAttachments.first(where: { $0.id == id }) {
            if let descriptor = capabilities.first(where: { $0.id == attachment.reference.id }) {
                HanlinCapabilityConfigurationView(
                    capability: descriptor,
                    attachment: Binding(
                        get: { draft.capabilityAttachments.first { $0.id == id } ?? attachment },
                        set: { draft.updateCapability($0) }),
                    onDone: { editingAttachmentID = nil })
            } else {
                ContentUnavailableView {
                    Label(attachment.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text("hanlin.composer.capabilities.unavailable", bundle: HanlinLocalization.bundle)
                } actions: {
                    Button(role: .destructive) {
                        draft.removeCapability(id: id)
                        editingAttachmentID = nil
                    } label: {
                        Text("hanlin.composer.capabilities.remove", bundle: HanlinLocalization.bundle)
                    }
                }
            }
        } else {
            HanlinCapabilityPicker(capabilities: capabilities,
                                   attachments: draft?.capabilityAttachments ?? [],
                                   onSelect: onAttach)
        }
    }
}
