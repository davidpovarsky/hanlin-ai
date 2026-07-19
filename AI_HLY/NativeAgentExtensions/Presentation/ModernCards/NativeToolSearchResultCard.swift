import SwiftUI

struct NativeToolSearchResultCard: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?
    let onViewAll: () -> Void

    private var visibleItems: [NativeUIListItem] {
        Array(block.items.prefix(min(block.compactItemLimit ?? 3, 3)))
    }

    var body: some View {
        NativeToolResultCardContainer(
            title: block.title ?? String(localized: "Search Results"),
            subtitle: resultCount,
            systemImage: block.systemImage ?? "magnifyingglass",
            actions: block.actions,
            onLaunchRequest: onLaunchRequest,
            onViewAll: block.items.count > visibleItems.count ? onViewAll : nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let body = item.body, !body.isEmpty {
                            Text(body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        NativeActionControlGroup(
                            actions: itemActions(item),
                            onLaunchRequest: onLaunchRequest
                        )
                    }
                    .padding(.vertical, 9)
                    if index < visibleItems.count - 1 {
                        Divider().opacity(0.55)
                    }
                }
            }
        }
    }

    private var resultCount: String? {
        guard !block.items.isEmpty else { return block.subtitle }
        return String(format: String(localized: "%lld results"), Int64(block.items.count))
    }

    private func itemActions(_ item: NativeUIListItem) -> [NativeUIAction] {
        guard let url = item.url,
              !item.actions.contains(where: { $0.type == .openURL }) else { return item.actions }
        return item.actions + [
            NativeUIAction(
                type: .openURL,
                title: String(localized: "Open"),
                systemImage: "arrow.up.right.square",
                url: url
            )
        ]
    }
}
