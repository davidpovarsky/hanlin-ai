import SwiftUI

struct AgentInlineProcessItemView: View {
    let item: AgentTranscriptItem
    let activity: AgentDisplayActivity?
    let onSelectActivity: (String) -> Void

    var body: some View {
        switch item.kind {
        case .assistantText, .reasoning, .progress:
            if let text = nonempty(item.text) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(item.kind == .progress ? 3 : 8)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        case .toolActivity:
            Button {
                AgentActivityTrace.selected(item: item)
                onSelectActivity(selectionID)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: activity?.systemImage ?? "sparkles")
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity?.title ?? String(localized: "Using a tool"))
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                            .lineLimit(2)
                        if let summary = toolSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Open activity"))
        case .error:
            if let text = nonempty(item.text) {
                Label(text, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        case .userVisibleToolResult:
            EmptyView()
        }
    }

    private var selectionID: String {
        item.externalID ?? item.id.uuidString
    }

    private var statusColor: Color {
        item.status == .failed || item.status == .cancelled ? .red : .secondary
    }

    private var toolSummary: String? {
        guard let text = nonempty(item.text),
              AgentActivityDeduplicator.normalized(text)
                != AgentActivityDeduplicator.normalized(activity?.title) else { return nil }
        return text
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
