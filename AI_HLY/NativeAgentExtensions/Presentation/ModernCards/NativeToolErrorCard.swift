import SwiftUI

struct NativeToolErrorCard: View {
    let block: NativeUIBlock
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        NativeToolResultCardContainer(
            title: block.title ?? String(localized: "Couldn’t load the source"),
            subtitle: nil,
            systemImage: block.systemImage ?? "exclamationmark.triangle",
            actions: block.actions,
            onLaunchRequest: onLaunchRequest,
            onViewAll: nil
        ) {
            if let body = block.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .tint(.orange)
    }
}
