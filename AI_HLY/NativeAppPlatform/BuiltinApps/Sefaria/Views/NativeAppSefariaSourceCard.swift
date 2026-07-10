import SwiftUI

struct NativeAppSefariaSourceCard: View {
    let source: NativeAppSefariaSource
    let language: NativeAppSefariaLanguage
    let mode: NativePresentationMode

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(source.ref, systemImage: "book.closed")
                    .font(.headline)

                if language != .english,
                   let hebrew = source.heText,
                   !hebrew.isEmpty {
                    Text(hebrew)
                        .font(mode == .chatCard ? .callout : .body)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                        .textSelection(.enabled)
                }

                if language != .hebrew, !source.text.isEmpty {
                    Text(source.text)
                        .font(mode == .chatCard ? .callout : .body)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
