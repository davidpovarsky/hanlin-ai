import HanlinLocalization
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import HanlinPresentationKit

public struct HanlinSourcesButton: View {
    public let sources: [HanlinSourceReference]
    public let title: String
    public let action: @MainActor () -> Void
    public init(sources: [HanlinSourceReference], title: String, action: @escaping @MainActor () -> Void) {
        self.sources = sources; self.title = title; self.action = action
    }
    public var body: some View {
        if !sources.isEmpty {
            Button(action: action) {
                HStack(spacing: 6) {
                    ForEach(Array(sources.prefix(3))) { source in HanlinSourceIcon(url: source.iconURL) }
                    Text(title).font(HanlinTypography.caption.weight(.medium))
                    Text("\(sources.count)", bundle: HanlinLocalization.bundle).font(HanlinTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.quaternary, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("hanlin-all-sources")
        }
    }
}

public struct HanlinSourcesList: View {
    @Environment(\.dismiss) private var dismiss
    public let sources: [HanlinSourceReference]
    public let title: String
    public let open: @MainActor (HanlinSourceReference) -> Void
    public init(sources: [HanlinSourceReference], title: String, open: @escaping @MainActor (HanlinSourceReference) -> Void) {
        self.sources = sources; self.title = title; self.open = open
    }
    // Adapt the source sheet to its actual content instead of leaving large empty space.
    private var listHeight: CGFloat {
        min(max(CGFloat(sources.count) * 62 + 36, 140), 500)
    }

    public var body: some View {
        NavigationStack {
            List(sources) { source in
                Button { open(source) } label: {
                    HStack(spacing: 12) {
                        HanlinSourceIcon(url: source.iconURL)
                        Text(source.title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-source-\(source.id)")
            }.frame(height: listHeight)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(hanlin: "Done") { dismiss() }
                            .accessibilityIdentifier("hanlin-sources-close")
                    }
                }
        }.presentationSizing(.fitted)
            .accessibilityIdentifier("hanlin-scoped-sources")
    }
}

private struct HanlinSourceIcon: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit() }
            placeholder: { Image(systemName: "globe").foregroundStyle(.secondary) }
            .frame(width: 16, height: 16).accessibilityHidden(true)
    }
}
#endif
