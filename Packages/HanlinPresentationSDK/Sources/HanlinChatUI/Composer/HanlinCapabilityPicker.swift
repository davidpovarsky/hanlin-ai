import SwiftUI
import HanlinLocalization
import HanlinPlatformContracts

/// The shared selection surface. Its only effect is returning a descriptor;
/// the embedding host owns the draft and decides when to send the request.
public struct HanlinCapabilityPicker: View {
    public let capabilities: [HanlinComposerCapabilityDescriptor]
    public let attachments: [HanlinCapabilityAttachment]
    public let onSelect: (HanlinComposerCapabilityDescriptor, String?) -> Void
    @State private var query = ""

    public init(capabilities: [HanlinComposerCapabilityDescriptor],
                attachments: [HanlinCapabilityAttachment],
                onSelect: @escaping (HanlinComposerCapabilityDescriptor, String?) -> Void) {
        self.capabilities = capabilities
        self.attachments = attachments
        self.onSelect = onSelect
    }

    private var filtered: [HanlinComposerCapabilityDescriptor] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return capabilities.filter {
            term.isEmpty || $0.title.localizedStandardContains(term)
                || $0.summary.localizedStandardContains(term)
                || $0.reference.capabilityID.localizedStandardContains(term)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "hanlin.composer.capabilities.search", bundle: HanlinLocalization.bundle),
                      text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("hanlin-capability-search")
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(filtered) { capability in
                    if capability.actions.isEmpty {
                        Button { onSelect(capability, nil) } label: { row(capability) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("hanlin-capability-attach-\(capability.id)")
                    } else {
                        Menu {
                            Button {
                                onSelect(capability, nil)
                            } label: {
                                Label(String(localized: "hanlin.composer.capabilities.chooseActionAutomatically",
                                             bundle: HanlinLocalization.bundle), systemImage: "sparkles")
                            }
                            .accessibilityIdentifier("hanlin-capability-action-automatic-\(capability.id)")
                            ForEach(capability.actions) { action in
                                Button { onSelect(capability, action.id) } label: {
                                    if attachments.contains(where: {
                                        $0.reference.id == capability.id && $0.actionID == action.id
                                    }) {
                                        Label(action.title, systemImage: "checkmark")
                                    } else {
                                        Text(action.title)
                                    }
                                }
                                .accessibilityIdentifier("hanlin-capability-action-\(capability.id)-\(action.id)")
                            }
                        } label: { row(capability) }
                        .accessibilityIdentifier("hanlin-capability-attach-\(capability.id)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-capability-picker")
    }

    private func row(_ capability: HanlinComposerCapabilityDescriptor) -> some View {
        HStack(spacing: 10) {
            Image(systemName: capability.systemImage)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.title).font(.subheadline.weight(.semibold))
                if !capability.summary.isEmpty {
                    Text(capability.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(capability.reference.kind.composerTitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: attachments.contains { $0.reference.id == capability.id }
                  ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

extension HanlinCapabilityKind {
    var composerTitle: String {
        switch self {
        case .tool: String(localized: "hanlin.composer.capabilities.tool", bundle: HanlinLocalization.bundle)
        case .miniApp: String(localized: "hanlin.composer.capabilities.miniApp", bundle: HanlinLocalization.bundle)
        case .skill: String(localized: "hanlin.composer.capabilities.skill", bundle: HanlinLocalization.bundle)
        case .mcp: String(localized: "hanlin.composer.capabilities.mcp", bundle: HanlinLocalization.bundle)
        }
    }

    var composerSymbol: String {
        switch self {
        case .tool: "wrench"
        case .miniApp: "square.grid.2x2"
        case .skill: "sparkles"
        case .mcp: "server.rack"
        }
    }
}
