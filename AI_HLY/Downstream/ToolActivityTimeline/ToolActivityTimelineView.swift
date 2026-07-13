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

    private var durationText: String {
        guard let footnote = block.footnote, !footnote.isEmpty else { return String(localized: "Worked") }
        return String(localized: "Worked for \(footnote)")
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Text(durationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                ForEach(steps.prefix(4)) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: step.systemImage ?? defaultSystemImage(for: step.type))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(step.title ?? defaultTitle(for: step.type))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            ToolActivityInspectorView(block: block, onLaunchRequest: onLaunchRequest)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.regularMaterial)
        }
        .accessibilityLabel(String(localized: "Open tool activity"))
    }

    private func defaultTitle(for type: NativeUIBlockType) -> String {
        switch type {
        case .searchResults: return String(localized: "Searched the web")
        case .calculation: return String(localized: "Calculated result")
        case .source: return String(localized: "Read source")
        case .error: return String(localized: "Tool failed")
        default: return String(localized: "Used a tool")
        }
    }

    private func defaultSystemImage(for type: NativeUIBlockType) -> String {
        switch type {
        case .searchResults: return "globe"
        case .calculation: return "function"
        case .source: return "doc.text.magnifyingglass"
        case .error: return "exclamationmark.triangle"
        default: return "gearshape.2"
        }
    }
}

private struct ToolActivityInspectorView: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

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
        }
    }
}

private struct ToolActivityStepView: View {
    let step: NativeUIBlock
    let isLast: Bool
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var isExpanded = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: step.systemImage ?? "gearshape.2")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(step.type == .error ? .red : .secondary)
                    .frame(width: 24, height: 24)

                if !isLast {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 1)
                        .frame(minHeight: 38)
                }
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if let subtitle = step.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let body = step.body, !body.isEmpty {
                        Text(body)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
                    }
                    if !step.keyValues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(step.keyValues) { pair in
                                LabeledContent(pair.key) {
                                    Text(pair.value)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 12))
                    }
                    if !step.children.isEmpty {
                        NativeUIRenderer(blocks: step.children, onLaunchRequest: onLaunchRequest)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(step.title ?? String(localized: "Tool activity"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }
}
