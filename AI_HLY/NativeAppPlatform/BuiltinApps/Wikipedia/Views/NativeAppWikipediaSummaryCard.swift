import SwiftUI

struct NativeAppWikipediaSummaryCard: View {
    let summary: NativeAppWikipediaSummary
    let mode: NativePresentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thumbnailURL = summary.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: mode == .chatCard ? 120 : 210)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Label(summary.title, systemImage: "globe")
                .font(.title3.weight(.semibold))

            if let description = summary.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }

            if !summary.extract.isEmpty {
                Text(summary.extract)
                    .font(mode == .chatCard ? .callout : .body)
                    .textSelection(.enabled)
            }

            if let url = summary.url {
                Link("Open Wikipedia", destination: url)
            }
        }
        .padding(.vertical, 4)
    }
}
