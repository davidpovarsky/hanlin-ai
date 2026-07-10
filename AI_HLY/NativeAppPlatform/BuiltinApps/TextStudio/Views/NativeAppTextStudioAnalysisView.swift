import SwiftUI

struct NativeAppTextStudioAnalysisView: View {
    let service: NativeAppTextStudioService
    @ObservedObject var store: NativeAppTextStudioStore

    @State private var analysis: NativeAppTextStudioAnalysis?

    var body: some View {
        List {
            Section {
                Button {
                    analyze()
                } label: {
                    Label("Analyze Current Draft", systemImage: "chart.bar.doc.horizontal")
                }
                .disabled(store.draft.isEmpty)
            }

            if let analysis {
                Section("Statistics") {
                    LabeledContent("Characters", value: "\(analysis.characters)")
                    LabeledContent("Without Spaces", value: "\(analysis.charactersWithoutSpaces)")
                    LabeledContent("Words", value: "\(analysis.words)")
                    LabeledContent("Sentences", value: "\(analysis.sentences)")
                    LabeledContent("Paragraphs", value: "\(analysis.paragraphs)")
                    LabeledContent("Lines", value: "\(analysis.lines)")
                }

                Section("Top Words") {
                    if analysis.topWords.isEmpty {
                        Text("No repeated words found.").foregroundStyle(.secondary)
                    } else {
                        ForEach(analysis.topWords) { item in
                            LabeledContent(item.word, value: "\(item.count)")
                        }
                    }
                }

                Section("Detected Content") {
                    NativeAppTextStudioDetectedList(title: "Links", values: analysis.links)
                    NativeAppTextStudioDetectedList(title: "Emails", values: analysis.emails)
                    NativeAppTextStudioDetectedList(title: "Numbers", values: analysis.numbers)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Analysis Yet",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Write or paste text in the Editor, then analyze it here.")
                    )
                }
            }
        }
        .navigationTitle("Analyze")
    }

    private func analyze() {
        let value = service.analyze(store.draft)
        analysis = value
        store.addHistory(
            operation: "Analysis",
            input: store.draft,
            output: "Words: \(value.words), Sentences: \(value.sentences), Links: \(value.links.count)"
        )
    }
}

private struct NativeAppTextStudioDetectedList: View {
    let title: String
    let values: [String]

    var body: some View {
        DisclosureGroup("\(title) (\(values.count))") {
            if values.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value).textSelection(.enabled)
                }
            }
        }
    }
}
