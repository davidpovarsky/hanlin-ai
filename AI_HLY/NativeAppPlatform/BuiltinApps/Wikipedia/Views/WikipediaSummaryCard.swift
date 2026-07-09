import SwiftUI

struct WikipediaSummaryCard: View {
    let summary: WikipediaSummary
    let mode: NativePresentationMode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(summary.title, systemImage: "globe")
                    .font(.headline)
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
        }
    }
}
