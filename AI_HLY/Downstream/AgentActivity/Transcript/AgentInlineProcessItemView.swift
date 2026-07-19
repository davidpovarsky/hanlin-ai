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
                        .foregroundStyle(item.status == .failed ? Color.red : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity?.title ?? item.text ?? String(localized: "Using a tool"))
                            .font(.subheadline)
                            .foregroundStyle(item.status == .failed ? Color.red : Color.secondary)
                            .lineLimit(2)
                        if let summary = activity?.narrativeText, summary != activity?.title {
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
            }
        case .userVisibleToolResult:
            EmptyView()
        }
    }

    private var selectionID: String {
        item.externalID ?? item.id.uuidString
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
