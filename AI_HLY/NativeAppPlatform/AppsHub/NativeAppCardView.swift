import SwiftUI

struct NativeAppCardView: View {
    let manifest: NativeAppManifest

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(manifest.title)
                        .font(.headline)
                    if manifest.isExperimental {
                        Text("Beta")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                Text(manifest.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(manifest.entryPoints.map(\.title).sorted().joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: manifest.systemImage)
                .font(.title2)
        }
    }
}
