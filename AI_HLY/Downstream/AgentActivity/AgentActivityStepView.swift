//
//  AgentActivityStepView.swift
//  AI_HLY
//

import SwiftUI

struct AgentActivityStepView: View {
    let step: AgentActivityStep
    let isLast: Bool
    var onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: statusImage)
                    .foregroundStyle(statusColor)
                    .frame(width: 24, height: 24)
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(minHeight: 36)
                }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    if let summary = step.userFacingSummary, summary != step.title {
                        Text(summary)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    if !step.queryItems.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(step.queryItems, id: \.self) { query in
                                    Text(query)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    if let input = step.input, !input.isEmpty {
                        contentCard(title: String(localized: "Input"), text: input, monospaced: step.kind == .codeExecution)
                    }
                    if let output = step.output, !output.isEmpty {
                        contentCard(title: String(localized: "Output"), text: output, monospaced: step.kind == .codeExecution)
                    }
                    if let error = step.errorDescription, !error.isEmpty {
                        contentCard(title: String(localized: "Failed"), text: error, monospaced: false)
                    }
                    if !step.sourceItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Reading a source"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(step.sourceItems) { source in
                                if let urlString = source.url, let url = URL(string: urlString) {
                                    Link(destination: url) {
                                        Label(source.title, systemImage: "arrow.up.right.square")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    Label(source.title, systemImage: "doc.text")
                                }
                            }
                        }
                    }
                    if !step.richResultBlocks.isEmpty {
                        NativeUIRenderer(blocks: step.richResultBlocks, presentationMode: .expanded, onLaunchRequest: onLaunchRequest)
                    }
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.body.weight(step.status == .running ? .semibold : .regular))
                    if let subtitle = step.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(step.status.localizedDescription)
    }

    @ViewBuilder
    private func contentCard(title: String, text: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusImage: String {
        switch step.status {
        case .pending: return "circle"
        case .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .failed: return .red
        case .cancelled: return .orange
        case .running: return .accentColor
        case .pending, .completed: return .secondary
        }
    }
}

private extension AgentActivityStatus {
    var localizedDescription: String {
        switch self {
        case .pending: return String(localized: "Working…")
        case .running: return String(localized: "Working…")
        case .completed: return String(localized: "Done")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}
