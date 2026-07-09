import SwiftUI

struct NativeAppSefariaSourceCard: View {
    let source: NativeAppSefariaSource
    let mode: NativePresentationMode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label(source.ref, systemImage: "book.closed")
                    .font(.headline)

                if !source.text.isEmpty {
                    Text(source.text)
                        .font(mode == .chatCard ? .callout : .body)
                        .textSelection(.enabled)
                }

                if let heText = source.heText, !heText.isEmpty {
                    Divider()
                    Text(heText)
                        .font(mode == .chatCard ? .callout : .body)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .textSelection(.enabled)
                }

                if let url = source.url {
                    Link("Open on Sefaria", destination: url)
                }
            }
        }
    }
}
