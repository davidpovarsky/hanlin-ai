//
//  NativeUIRenderer.swift
//  AI_HLY
//
//  Native SwiftUI renderer for NativeUIBlock tool results.
//  Prefer system components: GroupBox, DisclosureGroup, LabeledContent, ControlGroup, Label, Button and Link.
//

import SwiftUI
import UIKit

struct NativeUIRenderer: View {
    let blocks: [NativeUIBlock]
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    init(blocks: [NativeUIBlock], onLaunchRequest: ((NativeAppLaunchRequest) -> Void)? = nil) {
        self.blocks = blocks
        self.onLaunchRequest = onLaunchRequest
    }

    var body: some View {
        ForEach(blocks) { block in
            NativeUIBlockView(block: block, onLaunchRequest: onLaunchRequest)
        }
    }
}

private struct NativeUIBlockView: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        switch block.type {
        case .text:
            if let body = block.body {
                Text(body)
                    .textSelection(.enabled)
            }
        case .markdown:
            NativeMarkdownText(block.body ?? "")
        case .card, .source, .wikipediaSummary, .calculation, .error:
            NativeCardView(block: block, onLaunchRequest: onLaunchRequest)
        case .searchResults:
            NativeSearchResultsView(block: block, onLaunchRequest: onLaunchRequest)
        case .keyValueList:
            NativeKeyValueListView(block: block, onLaunchRequest: onLaunchRequest)
        }
    }
}

private struct NativeCardView: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        GroupBox {
            if let subtitle = block.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let body = block.body, !body.isEmpty {
                NativeMarkdownText(body)
                    .textSelection(.enabled)
            }
            if !block.keyValues.isEmpty {
                NativeKeyValueListView(block: block, onLaunchRequest: onLaunchRequest)
            }
            if !block.actions.isEmpty {
                NativeActionControlGroup(actions: block.actions, onLaunchRequest: onLaunchRequest)
            }
            if !block.children.isEmpty {
                NativeUIRenderer(blocks: block.children, onLaunchRequest: onLaunchRequest)
            }
            if let footnote = block.footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } label: {
            Label(block.title ?? defaultTitle(for: block.type), systemImage: block.systemImage ?? defaultSystemImage(for: block.type))
        }
        .groupBoxStyle(.automatic)
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
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        GroupBox {
            if let subtitle = block.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(block.items) { item in
                DisclosureGroup {
                    if let body = item.body, !body.isEmpty {
                        NativeMarkdownText(body)
                            .textSelection(.enabled)
                    }
                    NativeActionControlGroup(actions: item.actions + defaultActions(for: item), onLaunchRequest: onLaunchRequest)
                } label: {
                    Label {
                        Text(item.title)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: block.systemImage ?? "magnifyingglass")
                    }
                }
            }
            if !block.actions.isEmpty {
                NativeActionControlGroup(actions: block.actions, onLaunchRequest: onLaunchRequest)
            }
        } label: {
            Label(block.title ?? String(localized: "Search Results"), systemImage: block.systemImage ?? "magnifyingglass")
        }
        .groupBoxStyle(.automatic)
    }

    private func defaultActions(for item: NativeUIListItem) -> [NativeUIAction] {
        guard let url = item.url else { return [] }
        return [NativeUIAction(type: .openURL, title: String(localized: "Open"), systemImage: "safari", url: url)]
    }
}

private struct NativeKeyValueListView: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        GroupBox {
            ForEach(block.keyValues) { pair in
                LabeledContent(pair.key) {
                    Text(pair.value)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
            }
        } label: {
            if let title = block.title {
                Label(title, systemImage: block.systemImage ?? "list.bullet.rectangle")
            }
        }
        if !block.actions.isEmpty {
            NativeActionControlGroup(actions: block.actions, onLaunchRequest: onLaunchRequest)
        }
    }
}

private struct NativeActionControlGroup: View {
    let actions: [NativeUIAction]
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        if !actions.isEmpty {
            ControlGroup {
                ForEach(actions) { action in
                    NativeActionButton(action: action, onLaunchRequest: onLaunchRequest)
                }
            }
            .controlGroupStyle(.automatic)
        }
    }
}

private struct NativeActionButton: View {
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
            onLaunchRequest?(NativeAppRouter().launchRequest(
                route: route,
                presentationStyle: action.presentationStyle ?? .fullScreen
            ))
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

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        if let attributed = try? AttributedString(markdown: raw) {
            Text(attributed)
        } else {
            Text(raw)
        }
    }
}
