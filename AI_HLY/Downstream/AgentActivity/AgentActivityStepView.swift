import SwiftUI

struct AgentActivityStepView: View {
    let activity: AgentDisplayActivity
    let isLast: Bool
    var onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var showsDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                    .frame(width: 18, height: 18)
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                        .frame(minHeight: 28)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                if activity.isExpandable {
                    Button {
                        withAnimation(.smooth) { showsDetails.toggle() }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            title
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showsDetails ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    title
                }

                if showsDetails && activity.isExpandable {
                    details
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, 13)
        }
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        Group {
            if activity.kind == .narrative {
                Text(activity.narrativeText ?? activity.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(activity.title)
                    .font(.subheadline.weight(activity.status == .running ? .medium : .regular))
                    .foregroundStyle(activity.status == .failed ? .red : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !activity.queries.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(activity.queries, id: \.self) { query in
                            Text(query)
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if let input = activity.inputPreview {
                detailText(input, monospaced: activity.kind == .code)
            }
            if let output = activity.outputPreview {
                detailText(output, monospaced: activity.kind == .code)
            }
            if let error = activity.errorDescription {
                detailText(error, monospaced: false).foregroundStyle(.red)
            }
            ForEach(activity.sources) { source in
                if let url = source.url.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Label(source.title, systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Label(source.title, systemImage: "doc.text")
                        .font(.caption)
                }
            }
            if !activity.richResultBlocks.isEmpty {
                NativeUIRenderer(
                    blocks: activity.richResultBlocks,
                    presentationMode: .expanded,
                    onLaunchRequest: onLaunchRequest
                )
            }
        }
    }

    private func detailText(_ text: String, monospaced: Bool) -> some View {
        Text(text)
            .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var iconName: String {
        switch activity.kind {
        case .narrative: return "circle.fill"
        case .search: return "magnifyingglass"
        case .source, .document: return "doc.text"
        case .code: return "terminal"
        case .map: return "map"
        case .calendar: return "calendar"
        case .health: return "heart.text.square"
        case .tool: return "wrench.and.screwdriver"
        case .result: return "sparkles"
        case .error: return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        activity.status == .failed ? .red : .secondary
    }
}
