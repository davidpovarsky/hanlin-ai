import SwiftUI
import HanlinLocalization
import HanlinPlatformContracts

/// Explicit message choices, distinct from the host's enabled-capability chips.
public struct HanlinCapabilityAttachmentChips: View {
    public let attachments: [HanlinCapabilityAttachment]
    public let capabilities: [HanlinComposerCapabilityDescriptor]
    public let onEdit: ((HanlinCapabilityAttachment) -> Void)?
    public let onRemove: ((UUID) -> Void)?

    public init(attachments: [HanlinCapabilityAttachment],
                capabilities: [HanlinComposerCapabilityDescriptor] = [],
                onEdit: ((HanlinCapabilityAttachment) -> Void)? = nil,
                onRemove: ((UUID) -> Void)? = nil) {
        self.attachments = attachments
        self.capabilities = capabilities
        self.onEdit = onEdit
        self.onRemove = onRemove
    }

    public var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 6) {
                            if let onEdit {
                                Button { onEdit(attachment) } label: { attachmentLabel(attachment) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("hanlin-capability-edit-\(attachment.id.uuidString)-\(attachment.reference.id)")
                            } else {
                                attachmentLabel(attachment)
                            }
                            if let onRemove {
                                Button { onRemove(attachment.id) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "hanlin.composer.capabilities.remove",
                                                           bundle: HanlinLocalization.bundle) + " " + attachment.title)
                                .accessibilityIdentifier("hanlin-capability-remove-\(attachment.id.uuidString)")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .accessibilityElement(children: .contain)
                    }
                }
                .padding(.horizontal, 12)
            }
            .accessibilityIdentifier("hanlin-capability-attachments")
        }
    }

    private func attachmentLabel(_ attachment: HanlinCapabilityAttachment) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.title).font(.subheadline.weight(.medium)).lineLimit(1)
                let detail = summary(for: attachment)
                if !detail.isEmpty {
                    Text(detail).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: attachment.reference.kind.composerSymbol)
        }
    }

    private func summary(for attachment: HanlinCapabilityAttachment) -> String {
        let descriptor = capabilities.first { $0.id == attachment.reference.id }
        var parts: [String] = []
        if let actionID = attachment.actionID {
            parts.append(descriptor?.actions.first { $0.id == actionID }?.title ?? actionID)
        }
        if let schema = descriptor?.configuration, case let .object(values) = attachment.configuration {
            for field in schema.panels.flatMap(\.fields) {
                guard let value = values[field.key] else { continue }
                let display: String
                switch value {
                case let .string(text): display = optionTitle(text, options: field.options) ?? text
                case let .array(items):
                    display = items.compactMap {
                        if case let .string(id) = $0 { return optionTitle(id, options: field.options) ?? id }
                        return nil
                    }.joined(separator: ", ")
                case let .bool(enabled):
                    display = enabled ? String(localized: "hanlin.composer.capabilities.on", bundle: HanlinLocalization.bundle)
                                      : String(localized: "hanlin.composer.capabilities.off", bundle: HanlinLocalization.bundle)
                case let .number(number): display = number.formatted()
                case let .integer(number): display = number.formatted()
                case let .object(location):
                    if let latitude = location["latitude"]?.composerNumber,
                       let longitude = location["longitude"]?.composerNumber {
                        let coordinates = "\(latitude.formatted(.number.precision(.fractionLength(3)))), \(longitude.formatted(.number.precision(.fractionLength(3))))"
                        if let radius = location["radiusMeters"]?.composerNumber {
                            display = coordinates + " · " + radius.formatted() + " m"
                        } else {
                            display = coordinates
                        }
                    } else { display = "" }
                case .null: display = ""
                }
                if !display.isEmpty { parts.append("\(field.title): \(display)") }
            }
        }
        return parts.prefix(3).joined(separator: " · ")
    }

    private func optionTitle(_ id: String, options: [HanlinComposerOption]) -> String? {
        for option in options {
            if option.id == id { return option.title }
            if let title = optionTitle(id, options: option.children) { return title }
        }
        return nil
    }
}

extension HanlinJSONValue {
    var composerNumber: Double? {
        switch self {
        case let .number(value): value
        case let .integer(value): Double(value)
        default: nil
        }
    }
}

/// Read-only rendering for a submitted message or another SDK host.
public struct HanlinCapabilityAttachmentSummary: View {
    public let attachments: [HanlinCapabilityAttachment]
    public let capabilities: [HanlinComposerCapabilityDescriptor]

    public init(attachments: [HanlinCapabilityAttachment],
                capabilities: [HanlinComposerCapabilityDescriptor] = []) {
        self.attachments = attachments
        self.capabilities = capabilities
    }

    public var body: some View {
        HanlinCapabilityAttachmentChips(attachments: attachments, capabilities: capabilities)
    }
}
