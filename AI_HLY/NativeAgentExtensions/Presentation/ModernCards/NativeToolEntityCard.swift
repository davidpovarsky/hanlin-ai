import SwiftUI

struct NativeToolEntityCard: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?
    let onViewAll: () -> Void

    var body: some View {
        NativeToolResultCardContainer(
            title: block.title ?? defaultTitle,
            subtitle: block.subtitle,
            systemImage: block.systemImage ?? defaultImage,
            actions: safeActions,
            onLaunchRequest: onLaunchRequest,
            onViewAll: hasMoreContent ? onViewAll : nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let body = block.body, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .lineLimit(block.compactLineLimit ?? 4)
                        .textSelection(.enabled)
                }
                ForEach(block.keyValues.prefix(4)) { pair in
                    LabeledContent(pair.key) {
                        Text(pair.value)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .font(.subheadline)
                }
                if let footnote = block.footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var safeActions: [NativeUIAction] {
        guard let url = block.url,
              !block.actions.contains(where: { $0.type == .openURL }) else { return block.actions }
        return block.actions + [
            NativeUIAction(
                type: .openURL,
                title: String(localized: "Open"),
                systemImage: "arrow.up.right.square",
                url: url
            )
        ]
    }

    private var hasMoreContent: Bool {
        block.children.isEmpty == false
            || block.keyValues.count > 4
            || (block.body?.count ?? 0) > 360
    }

    private var defaultTitle: String {
        switch block.type {
        case .source: String(localized: "Source")
        case .wikipediaSummary: "Wikipedia"
        case .calculation: String(localized: "Calculation")
        default: String(localized: "Result card")
        }
    }

    private var defaultImage: String {
        switch block.type {
        case .source: "book.closed"
        case .wikipediaSummary: "globe"
        case .calculation: "function"
        case .keyValueList: "list.bullet.rectangle"
        default: "sparkles"
        }
    }
}
