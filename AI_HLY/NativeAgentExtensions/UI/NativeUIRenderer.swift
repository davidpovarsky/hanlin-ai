//
//  NativeUIRenderer.swift
//  AI_HLY
//
//  Provider-neutral compact and expanded rendering for Native UI tool results.
//

import SwiftUI
import UIKit

enum NativeUIPresentationMode: String {
    case compact
    case expanded
}

struct NativeUIExpandedPayload: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let blocks: [NativeUIBlock]
}

struct NativeUIToolResultContainer: View {
    let blocks: [NativeUIBlock]
    let temporaryRecord: Bool
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var sheetPayload: NativeUIExpandedPayload?
    @State private var fullScreenPayload: NativeUIExpandedPayload?

    private var canExpand: Bool {
        blocks.contains { ($0.allowsExpansion ?? true) && $0.hasExpandableContent }
    }

    private var expandedPresentation: NativeUIExpandedPresentation {
        blocks.compactMap(\.preferredExpandedPresentation).first ?? .sheet
    }

    private var title: String {
        blocks.compactMap(\.title).first ?? String(localized: "Tool Result")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NativeUIRenderer(
                blocks: blocks,
                presentationMode: .compact,
                onLaunchRequest: onLaunchRequest
            )
            .frame(maxHeight: 220, alignment: .top)
            .clipped()

            if canExpand {
                HStack {
                    Spacer()
                    Button {
                        openExpandedPresentation()
                    } label: {
                        Label(
                            String(localized: "Expand"),
                            systemImage: "arrow.down.backward.and.arrow.up.forward"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.95, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke((temporaryRecord ? Color.primary : Color.hlBluefont).opacity(0.22), lineWidth: 1)
        }
        .shadow(color: (temporaryRecord ? Color.primary : Color.hlBlue).opacity(0.2), radius: 2, y: 1)
        .foregroundColor(temporaryRecord ? .primary : .hlBluefont)
        .sheet(item: $sheetPayload) { payload in
            NativeUIExpandedView(payload: payload, onLaunchRequest: onLaunchRequest)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $fullScreenPayload) { payload in
            NativeUIExpandedView(payload: payload, onLaunchRequest: onLaunchRequest)
        }
        .onAppear {
            logPresentation("native_ui_compact_displayed", mode: .compact)
        }
    }

    private func openExpandedPresentation() {
        let payload = NativeUIExpandedPayload(title: title, blocks: blocks)
        switch expandedPresentation {
        case .sheet:
            sheetPayload = payload
        case .fullScreen:
            fullScreenPayload = payload
        }
        NativeToolTraceLogger.shared.log(
            "native_ui_expanded_opened",
            presentationFields(mode: .expanded).merging(
                ["presentation": expandedPresentation.rawValue],
                uniquingKeysWith: { _, new in new }
            )
        )
    }

    private func logPresentation(_ event: String, mode: NativeUIPresentationMode) {
        NativeToolTraceLogger.shared.log(event, presentationFields(mode: mode))
    }

    private func presentationFields(mode: NativeUIPresentationMode) -> [String: Any] {
        [
            "presentationMode": mode.rawValue,
            "blockCount": blocks.count,
            "blockTypes": blocks.map { $0.type.rawValue },
            "itemCount": blocks.reduce(0) { $0 + $1.recursiveItemCount },
            "compactItemCount": blocks.reduce(0) {
                $0 + min($1.items.count, $1.compactItemLimit ?? 4)
            }
        ]
    }
}

private struct NativeUIExpandedView: View {
    let payload: NativeUIExpandedPayload
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                NativeUIRenderer(
                    blocks: payload.blocks,
                    presentationMode: .expanded,
                    onLaunchRequest: onLaunchRequest
                )
                .padding()
            }
            .navigationTitle(payload.title)
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
        .onDisappear {
            NativeToolTraceLogger.shared.log(
                "native_ui_expanded_closed",
                [
                    "blockCount": payload.blocks.count,
                    "blockTypes": payload.blocks.map { $0.type.rawValue },
                    "itemCount": payload.blocks.reduce(0) { $0 + $1.recursiveItemCount }
                ]
            )
        }
    }
}

struct NativeUIRenderer: View {
    let blocks: [NativeUIBlock]
    let presentationMode: NativeUIPresentationMode
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    init(
        blocks: [NativeUIBlock],
        presentationMode: NativeUIPresentationMode,
        onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil
    ) {
        self.blocks = blocks
        self.presentationMode = presentationMode
        self.onLaunchRequest = onLaunchRequest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                NativeUIBlockView(
                    block: block,
                    presentationMode: presentationMode,
                    onLaunchRequest: onLaunchRequest
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeUIBlockView: View {
    let block: NativeUIBlock
    let presentationMode: NativeUIPresentationMode
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        switch block.type {
        case .text:
            if let body = block.body {
                Text(body)
                    .lineLimit(presentationMode == .compact ? block.compactLineLimit ?? 8 : nil)
                    .nativeTextSelection(presentationMode == .expanded)
            }
        case .markdown:
            NativeMarkdownText(
                block.body ?? "",
                lineLimit: presentationMode == .compact ? block.compactLineLimit ?? 8 : nil,
                isSelectable: presentationMode == .expanded
            )
        case .card, .source, .wikipediaSummary, .calculation, .error:
            NativeCardView(
                block: block,
                presentationMode: presentationMode,
                onLaunchRequest: onLaunchRequest
            )
        case .searchResults:
            NativeSearchResultsView(
                block: block,
                presentationMode: presentationMode,
                onLaunchRequest: onLaunchRequest
            )
        case .keyValueList:
            NativeKeyValueListView(
                block: block,
                presentationMode: presentationMode,
                onLaunchRequest: onLaunchRequest
            )
        }
    }
}

private struct NativeCardView: View {
    let block: NativeUIBlock
    let presentationMode: NativeUIPresentationMode
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let subtitle = block.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(presentationMode == .compact ? 2 : nil)
                        .nativeTextSelection(presentationMode == .expanded)
                }
                if let body = block.body, !body.isEmpty {
                    NativeMarkdownText(
                        body,
                        lineLimit: presentationMode == .compact ? block.compactLineLimit ?? 8 : nil,
                        isSelectable: presentationMode == .expanded
                    )
                }
                if !block.keyValues.isEmpty {
                    NativeKeyValueRows(block: block, presentationMode: presentationMode)
                }
                NativeActionControlGroup(actions: block.actions, onLaunchRequest: onLaunchRequest)
                if !block.children.isEmpty {
                    NativeUIRenderer(
                        blocks: presentationMode == .compact
                            ? Array(block.children.prefix(block.compactItemLimit ?? 4))
                            : block.children,
                        presentationMode: presentationMode,
                        onLaunchRequest: onLaunchRequest
                    )
                }
                if let footnote = block.footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(presentationMode == .compact ? 2 : nil)
                        .nativeTextSelection(presentationMode == .expanded)
                }
            }
        } label: {
            Label(
                block.title ?? defaultTitle(for: block.type),
                systemImage: block.systemImage ?? defaultSystemImage(for: block.type)
            )
        }
    }

    private func defaultTitle(for type: NativeUIBlockType) -> String {
        switch type {
        case .source: return String(localized: "Source")
        case .wikipediaSummary: return "Wikipedia"
        case .calculation: return String(localized: "Calculation")
        case .error: return String(localized: "Error")
        default: return String(localized: "Result")
        }
    }

    private func defaultSystemImage(for type: NativeUIBlockType) -> String {
        switch type {
        case .source: return "book.closed"
        case .wikipediaSummary: return "globe"
        case .calculation: return "function"
        case .error: return "exclamationmark.triangle"
        default: return "sparkles"
        }
    }
}

private struct NativeSearchResultsView: View {
    let block: NativeUIBlock
    let presentationMode: NativeUIPresentationMode
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    private var visibleItems: [NativeUIListItem] {
        presentationMode == .compact
            ? Array(block.items.prefix(block.compactItemLimit ?? 4))
            : block.items
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let subtitle = block.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(presentationMode == .compact ? 1 : nil)
                }

                ForEach(visibleItems) { item in
                    if presentationMode == .compact {
                        compactItem(item)
                    } else {
                        expandedItem(item)
                    }
                }

                if presentationMode == .compact, block.items.count > visibleItems.count {
                    Text(
                        String(
                            format: String(localized: "%lld more results"),
                            Int64(block.items.count - visibleItems.count)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                NativeActionControlGroup(actions: block.actions, onLaunchRequest: onLaunchRequest)
            }
        } label: {
            Label(
                block.title ?? String(localized: "Search Results"),
                systemImage: block.systemImage ?? "magnifyingglass"
            )
        }
    }

    private func compactItem(_ item: NativeUIListItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(item.title).lineLimit(2)
            } icon: {
                Image(systemName: block.systemImage ?? "magnifyingglass")
            }
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let body = item.body, !body.isEmpty {
                NativeMarkdownText(body, lineLimit: 3, isSelectable: false)
                    .font(.subheadline)
            }
            NativeActionControlGroup(
                actions: item.actions + defaultActions(for: item),
                onLaunchRequest: onLaunchRequest
            )
        }
        .padding(.vertical, 4)
    }

    private func expandedItem(_ item: NativeUIListItem) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let body = item.body, !body.isEmpty {
                    NativeMarkdownText(body, lineLimit: nil, isSelectable: true)
                }
                NativeActionControlGroup(
                    actions: item.actions + defaultActions(for: item),
                    onLaunchRequest: onLaunchRequest
                )
            }
        } label: {
            Label(item.title, systemImage: block.systemImage ?? "magnifyingglass")
        }
    }

    private func defaultActions(for item: NativeUIListItem) -> [NativeUIAction] {
        guard let url = item.url,
              !item.actions.contains(where: { $0.type == .openURL }) else { return [] }
        return [
            NativeUIAction(
                type: .openURL,
                title: String(localized: "Open"),
                systemImage: "safari",
                url: url
            )
        ]
    }
}

private struct NativeKeyValueListView: View {
    let block: NativeUIBlock
    let presentationMode: NativeUIPresentationMode
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                NativeKeyValueRows(block: block, presentationMode: presentationMode)
                NativeActionControlGroup(actions: block.actions, onLaunchRequest: onLaunchRequest)
            }
        } label: {
            if let title = block.title {
                Label(title, systemImage: block.systemImage ?? "list.bullet.rectangle")
            }
        }
    }
}

private struct NativeKeyValueRows: View {
    let block: NativeUIBlock
    let presentationMode: NativeUIPresentationMode

    private var values: [NativeUIKeyValue] {
        presentationMode == .compact
            ? Array(block.keyValues.prefix(block.compactItemLimit ?? 4))
            : block.keyValues
    }

    var body: some View {
        ForEach(values) { pair in
            LabeledContent(pair.key) {
                Text(pair.value)
                    .multilineTextAlignment(.leading)
                    .lineLimit(presentationMode == .compact ? 2 : nil)
                    .nativeTextSelection(presentationMode == .expanded)
            }
        }
    }
}

struct NativeActionControlGroup: View {
    let actions: [NativeUIAction]
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        if !actions.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        NativeActionButton(action: action, onLaunchRequest: onLaunchRequest)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct NativeActionButton: View {
    let action: NativeUIAction
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            perform(action)
        } label: {
            Label(action.title, systemImage: action.systemImage ?? defaultSystemImage)
        }
    }

    private var defaultSystemImage: String {
        switch action.type {
        case .openURL: return "arrow.up.right.square"
        case .copyText: return "doc.on.doc"
        case .nativeAppAction, .openAppRoute: return "arrow.up.forward.app"
        }
    }

    private func perform(_ action: NativeUIAction) {
        switch action.type {
        case .openURL:
            guard let urlString = action.url, let url = URL(string: urlString) else { return }
            openURL(url)
        case .copyText:
            UIPasteboard.general.string = action.text ?? action.url ?? ""
        case .openAppRoute:
            guard let route = action.route else { return }
            onLaunchRequest?(
                NativeAppRouter().launchRequest(
                    route: route,
                    presentationStyle: action.presentationStyle ?? .fullScreen
                )
            )
        case .nativeAppAction:
            guard let nativeAction = action.nativeAction else { return }
            Task {
                let platform = NativeAppPlatformServices.default(
                    appID: nativeAction.appID ?? nativeAction.route?.appID,
                    modelContext: nil,
                    openURL: { url in openURL(url) },
                    capabilityRegistry: .shared
                )
                if case .launchRequested(let request) = await platform.actionBus.perform(nativeAction) {
                    onLaunchRequest?(request)
                }
            }
        }
    }
}

private struct NativeMarkdownText: View {
    let raw: String
    let lineLimit: Int?
    let isSelectable: Bool

    init(_ raw: String, lineLimit: Int?, isSelectable: Bool) {
        self.raw = raw
        self.lineLimit = lineLimit
        self.isSelectable = isSelectable
    }

    var body: some View {
        Group {
            if let attributed = try? AttributedString(markdown: raw) {
                Text(attributed)
            } else {
                Text(raw)
            }
        }
        .lineLimit(lineLimit)
        .nativeTextSelection(isSelectable)
    }
}

private extension View {
    @ViewBuilder
    func nativeTextSelection(_ isEnabled: Bool) -> some View {
        if isEnabled {
            textSelection(.enabled)
        } else {
            self
        }
    }
}

private extension NativeUIBlock {
    var recursiveItemCount: Int {
        items.count + children.reduce(0) { $0 + $1.recursiveItemCount }
    }

    var hasExpandableContent: Bool {
        let itemLimit = compactItemLimit ?? 4
        let lineLimit = compactLineLimit ?? 8
        return items.count > itemLimit
            || keyValues.count > itemLimit
            || !children.isEmpty
            || (body?.count ?? 0) > lineLimit * 24
            || type == .searchResults && !items.isEmpty
    }
}
