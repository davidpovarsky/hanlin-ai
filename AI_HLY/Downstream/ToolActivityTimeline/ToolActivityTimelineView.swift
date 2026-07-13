import SwiftUI

/// Downstream-only presentation layer for ChatGPT-style tool activity.
/// The upstream chat pipeline continues to emit `NativeUIBlock`; this view only changes presentation.
struct ToolActivityTimelineView: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var isPresented = false

    private var steps: [NativeUIBlock] {
        block.children.isEmpty ? [block] : block.children
    }

    private var status: NativeUIActivityStatus {
        block.activityStatus ?? aggregateStatus
    }

    private var aggregateStatus: NativeUIActivityStatus {
        if steps.contains(where: { $0.activityStatus == .running || $0.activityStatus == .pending }) { return .running }
        if steps.contains(where: { $0.activityStatus == .failed }) { return .failed }
        if steps.contains(where: { $0.activityStatus == .cancelled }) { return .cancelled }
        return .completed
    }

    private var headerText: String {
        switch status {
        case .pending, .running:
            return String(localized: "Working…")
        case .failed:
            return String(localized: "Work failed")
        case .cancelled:
            return String(localized: "Work cancelled")
        case .completed:
            guard let footnote = block.footnote, !footnote.isEmpty else {
                return String(localized: "Worked")
            }
            if footnote.localizedCaseInsensitiveContains("thought") || footnote.localizedCaseInsensitiveContains("worked") {
                return footnote
            }
            return String(localized: "Worked for \(footnote)")
        }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    statusIcon
                    Text(headerText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                ForEach(steps.prefix(4)) { step in
                    compactStep(step)
                }

                if steps.count > 4 {
                    Text(String(localized: "+ \(steps.count - 4) more"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            ToolActivityInspectorView(block: block, onLaunchRequest: onLaunchRequest)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Open tool activity"))
        .accessibilityHint(String(localized: "Shows the full sequence of tool actions"))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .pending, .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func compactStep(_ step: NativeUIBlock) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: step.systemImage ?? defaultSystemImage(for: step.type))
                .font(.subheadline)
                .foregroundStyle(step.activityStatus == .failed ? .red : .secondary)
                .frame(width: 18)
            Text(step.title ?? defaultTitle(for: step.type))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if step.activityStatus == .running || step.activityStatus == .pending {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private func defaultTitle(for type: NativeUIBlockType) -> String {
        switch type {
        case .searchResults: return String(localized: "Searched the web")
        case .calculation: return String(localized: "Calculated result")
        case .source: return String(localized: "Read source")
        case .error: return String(localized: "Tool failed")
        case .markdown: return String(localized: "Reasoned through the request")
        default: return String(localized: "Used a tool")
        }
    }

    private func defaultSystemImage(for type: NativeUIBlockType) -> String {
        switch type {
        case .searchResults: return "globe"
        case .calculation: return "function"
        case .source: return "doc.text.magnifyingglass"
        case .error: return "exclamationmark.triangle"
        case .markdown: return "sparkles"
        default: return "gearshape.2"
        }
    }
}

private struct ToolActivityInspectorView: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var steps: [NativeUIBlock] {
        block.children.isEmpty ? [block] : block.children
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        ToolActivityStepView(
                            step: step,
                            isLast: index == steps.count - 1,
                            onLaunchRequest: onLaunchRequest
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle(String(localized: "Thinking"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ToolActivityStepView: View {
    let step: NativeUIBlock
    let isLast: Bool
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var isExpanded = true

    private var status: NativeUIActivityStatus {
        step.activityStatus ?? .completed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                stepStatusIcon
                    .frame(width: 24, height: 24)

                if !isLast {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 1)
                        .frame(minHeight: 44)
                }
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let subtitle = step.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    queryChips
                    inputOutputContent

                    if !step.items.isEmpty || !step.keyValues.isEmpty || !step.actions.isEmpty || !step.children.isEmpty {
                        NativeUIRenderer(blocks: richResultBlocks, onLaunchRequest: onLaunchRequest)
                    }

                    if let footnote = step.footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.title ?? String(localized: "Tool activity"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    statusLabel
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    @ViewBuilder
    private var stepStatusIcon: some View {
        switch status {
        case .pending, .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: step.systemImage ?? "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .pending: Text(String(localized: "Pending"))
        case .running: Text(String(localized: "Running"))
        case .completed: Text(String(localized: "Done"))
        case .failed: Text(String(localized: "Failed"))
        case .cancelled: Text(String(localized: "Cancelled"))
        }
    }

    @ViewBuilder
    private var queryChips: some View {
        if !step.queryItems.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(step.queryItems, id: \.self) { query in
                        Text(query)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var inputOutputContent: some View {
        if let input = step.input, !input.isEmpty {
            detailCard(title: String(localized: "Input"), text: input, isCode: step.activityDetailStyle == .code)
        }

        if let output = step.output, !output.isEmpty {
            detailCard(title: String(localized: "Output"), text: output, isCode: step.activityDetailStyle == .code)
        } else if let body = step.body, !body.isEmpty {
            detailCard(title: nil, text: body, isCode: step.activityDetailStyle == .code)
        }
    }

    private func detailCard(title: String?, text: String, isCode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(isCode ? .system(.footnote, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private var richResultBlocks: [NativeUIBlock] {
        var result: [NativeUIBlock] = []
        if !step.items.isEmpty || !step.keyValues.isEmpty || !step.actions.isEmpty {
            result.append(
                NativeUIBlock(
                    type: step.type == .activityTimeline ? .card : step.type,
                    title: step.title,
                    subtitle: nil,
                    body: nil,
                    systemImage: step.systemImage,
                    imageURL: step.imageURL,
                    url: step.url,
                    items: step.items,
                    keyValues: step.keyValues,
                    actions: step.actions
                )
            )
        }
        result.append(contentsOf: step.children.filter { $0.type != .activityTimeline })
        return result
    }
}