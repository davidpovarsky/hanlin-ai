import SwiftUI

struct TextToolkitRootView: View {
    let service: TextToolkitService
    let context: NativeAppContext

    @State private var text = ""
    @State private var transform: TextToolkitTransform = .removeExtraSpaces
    @State private var transformed = ""

    private var analysis: TextToolkitAnalysis {
        service.analyze(text)
    }

    var body: some View {
        List {
            Section("Input") {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Analysis") {
                LabeledContent("Characters", value: String(analysis.characters))
                LabeledContent("Words", value: String(analysis.words))
                LabeledContent("Sentences", value: String(analysis.sentences))
                LabeledContent("Lines", value: String(analysis.lines))
                if !analysis.links.isEmpty {
                    DisclosureGroup("Links (\(analysis.links.count))") {
                        ForEach(analysis.links, id: \.self) { link in
                            Text(link).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }

            Section("Transform") {
                Picker("Transform", selection: $transform) {
                    ForEach(TextToolkitTransform.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                Button {
                    transformed = service.transform(text, transform: transform)
                } label: {
                    Label("Apply", systemImage: "wand.and.stars")
                }
                if !transformed.isEmpty {
                    Text(transformed).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Text Toolkit")
    }
}
