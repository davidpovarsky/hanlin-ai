//
//  AgentActivityInspectorView.swift
//  AI_HLY
//

import SwiftUI

struct AgentActivityInspectorView: View {
    let run: AgentRun
    let selectedActivityID: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timeline: AgentDisplayTimeline { AgentActivityComposer.compose(run) }
    private var thinkingItems: [AgentTranscriptItem] {
        run.transcriptItems
            .filter { $0.visibilityAfterCompletion == .collapseIntoThinking }
            .sorted { $0.sequence < $1.sequence }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if run.hasModernTranscript, !thinkingItems.isEmpty {
                            ForEach(thinkingItems) { item in
                                inspectorTranscriptItem(
                                    item,
                                    isLast: item.id == thinkingItems.last?.id
                                )
                                    .id(selectionID(for: item))
                            }
                        } else {
                            ForEach(Array(timeline.activities.enumerated()), id: \.element.id) { index, activity in
                                AgentInspectorActivityView(
                                    activity: activity,
                                    isSelected: selectedActivityID == activity.id,
                                    isLast: index == timeline.activities.count - 1
                                )
                                .id(activity.id)
                            }
                        }
                    }
                    .padding()
                }
                .task(id: selectedActivityID) {
                    guard let selectedActivityID else { return }
                    await Task.yield()
                    if reduceMotion {
                        proxy.scrollTo(selectedActivityID, anchor: .top)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(selectedActivityID, anchor: .top)
                        }
                    }
                    AgentActivityTrace.inspectorScrolled(
                        runID: run.id,
                        selectedActivityID: selectedActivityID
                    )
                }
            }
            .navigationTitle(String(localized: "Thinking"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(String(localized: "Close"), systemImage: "xmark")
                    }
                }
            }
        }
        .onAppear {
            AgentActivityTrace.inspectorOpened(
                runID: run.id,
                selectedActivityID: selectedActivityID
            )
        }
        .onDisappear {
            AgentActivityTrace.inspectorClosed(runID: run.id)
        }
    }

    @ViewBuilder
    private func inspectorTranscriptItem(_ item: AgentTranscriptItem, isLast: Bool) -> some View {
        let selected = selectedActivityID == selectionID(for: item)
        if item.kind == .assistantText || item.kind == .progress {
            if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                AgentTranscriptTextView(text: text, usesMathRenderer: false)
                    .padding(10)
                    .background(highlight(selected), in: RoundedRectangle(cornerRadius: 12))
            }
        } else if let activity = AgentTranscriptPresentation.activity(for: item, in: timeline) {
            AgentInspectorActivityView(activity: activity, isSelected: selected, isLast: isLast)
        } else if let text = item.text, !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
                .padding(10)
                .background(highlight(selected), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func selectionID(for item: AgentTranscriptItem) -> String {
        item.externalID ?? item.id.uuidString
    }

    private func highlight(_ selected: Bool) -> Color {
        selected ? Color.accentColor.opacity(0.09) : .clear
    }
}

private struct AgentInspectorActivityView: View {
    let activity: AgentDisplayActivity
    let isSelected: Bool
    let isLast: Bool

    @State private var showsAllQueries = false
    @State private var showsAllSources = false

    private var displayedQueries: [String] {
        showsAllQueries ? activity.queries : Array(activity.queries.prefix(8))
    }
    private var displayedSources: [AgentActivitySource] {
        showsAllSources ? activity.sources : Array(activity.sources.prefix(10))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(activity.status == .failed ? .red : .secondary)
                    .frame(width: 22, height: 22)
                if !isLast {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.45))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(activity.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            if !displayedQueries.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(displayedQueries, id: \.self) { query in
                        Label(query, systemImage: "magnifyingglass")
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            if activity.queries.count > 8 {
                showMoreButton(isExpanded: $showsAllQueries)
            }
            if let input = activity.inputPreview {
                detailText(input, monospaced: activity.kind == .code)
            }
            if let output = activity.outputPreview {
                detailText(output, monospaced: activity.kind == .code)
            }
            if let error = activity.errorDescription {
                detailText(error, monospaced: false)
                    .foregroundStyle(.red)
            }
                if !displayedSources.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: 6, alignment: .leading)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(displayedSources) { source in
                            if let url = source.url.flatMap(URL.init(string:)) {
                                Link(destination: url) {
                                    Label(sourceLabel(source), systemImage: "globe")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(.quaternary, in: Capsule())
                                }
                            } else {
                                Label(sourceLabel(source), systemImage: "doc.text")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
            if activity.sources.count > 10 {
                showMoreButton(isExpanded: $showsAllSources)
            }
            }
            .padding(.bottom, isLast ? 0 : 14)
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func detailText(_ text: String, monospaced: Bool) -> some View {
        Text(text)
            .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func showMoreButton(isExpanded: Binding<Bool>) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            Text(isExpanded.wrappedValue ? String(localized: "Show less") : String(localized: "Show more"))
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private func sourceLabel(_ source: AgentActivitySource) -> String {
        if let sourceName = source.sourceName, !sourceName.isEmpty { return sourceName }
        if let value = source.url, let host = URL(string: value)?.host() { return host }
        return source.title
    }

    private var statusText: String {
        switch activity.status {
        case .pending, .running: return String(localized: "Working…")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }

    private var iconName: String {
        if let systemImage = activity.systemImage { return systemImage }
        switch activity.kind {
        case .reasoning: return "bubble.left.and.text.bubble.right"
        case .narrative: return "circle.fill"
        case .search: return "magnifyingglass"
        case .source, .document: return "doc.text"
        case .code: return "terminal"
        case .map: return "map"
        case .calendar: return "calendar"
        case .health: return "heart.text.square"
        case .tool: return "sparkles"
        case .result: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        }
    }
}
