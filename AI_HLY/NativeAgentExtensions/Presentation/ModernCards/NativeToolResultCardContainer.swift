import SwiftUI

struct NativeToolResultCardContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let actions: [NativeUIAction]
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?
    let onViewAll: (() -> Void)?
    let content: Content

    init(
        title: String,
        subtitle: String?,
        systemImage: String,
        actions: [NativeUIAction],
        onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?,
        onViewAll: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.actions = actions
        self.onLaunchRequest = onLaunchRequest
        self.onViewAll = onViewAll
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NativeToolResultCardStyle.sectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            content

            if !actions.isEmpty || onViewAll != nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        NativeActionControlGroup(
                            actions: actions,
                            onLaunchRequest: onLaunchRequest
                        )
                        if let onViewAll {
                            Button(action: onViewAll) {
                                Label(String(localized: "View all"), systemImage: "list.bullet")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(minHeight: 44)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(NativeToolResultCardStyle.contentPadding)
        .frame(maxWidth: 640, alignment: .leading)
        .background(
            NativeToolResultCardStyle.background,
            in: RoundedRectangle(cornerRadius: NativeToolResultCardStyle.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NativeToolResultCardStyle.cornerRadius, style: .continuous)
                .stroke(NativeToolResultCardStyle.separator, lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
    }
}
