import Foundation

struct NativeAppTextStudioAnalyzeTool: NativeTool {
    let service: NativeAppTextStudioService
    let name = "app_text_analyze"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Text Studio Analysis",
            summary: "Analyze text using the same Core service as the Text Studio mini app.",
            categories: ["text", "analysis", "native app"],
            keywords: ["word count", "sentences", "links", "emails", "numbers", "analyze"],
            examples: ["Analyze this text", "Count words and extract links"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Analyze text using the compiled Text Studio Core.",
            parameters: NativeToolSchema.object(
                properties: ["text": NativeToolSchema.string(description: "Text to analyze.")],
                required: ["text"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let text = NativeAppJSON.string(object, "text")
        guard !text.isEmpty else { return NativeToolResult(modelText: "Missing text to analyze.") }
        let analysis = service.analyze(text)
        let values = [
            NativeUIKeyValue(key: "Characters", value: "\(analysis.characters)"),
            NativeUIKeyValue(key: "Words", value: "\(analysis.words)"),
            NativeUIKeyValue(key: "Sentences", value: "\(analysis.sentences)"),
            NativeUIKeyValue(key: "Paragraphs", value: "\(analysis.paragraphs)"),
            NativeUIKeyValue(key: "Links", value: "\(analysis.links.count)"),
            NativeUIKeyValue(key: "Emails", value: "\(analysis.emails.count)"),
            NativeUIKeyValue(key: "Numbers", value: "\(analysis.numbers.count)")
        ]
        let modelText = [
            "Text analysis:",
            "Characters: \(analysis.characters)",
            "Words: \(analysis.words)",
            "Sentences: \(analysis.sentences)",
            "Paragraphs: \(analysis.paragraphs)",
            "Links: \(analysis.links.joined(separator: ", "))",
            "Emails: \(analysis.emails.joined(separator: ", "))",
            "Numbers: \(analysis.numbers.joined(separator: ", "))"
        ].joined(separator: "\n")
        return NativeToolResult(
            modelText: modelText,
            userText: "Analyzed \(analysis.words) word(s).",
            uiBlocks: [NativeUIBlock(
                type: .keyValueList,
                title: "Text Analysis",
                keyValues: values,
                actions: [NativeUIAction(
                    type: .openAppRoute,
                    title: "Continue in Text Studio",
                    systemImage: "arrow.up.forward.app",
                    route: .textStudioEditor(text: text),
                    presentationStyle: .fullScreen
                )]
            )]
        )
    }
}

struct NativeAppTextStudioTransformTool: NativeTool {
    let service: NativeAppTextStudioService
    let name = "app_text_transform"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Text Studio Transform",
            summary: "Transform text using the same Core service as the Text Studio mini app.",
            categories: ["text", "formatting", "native app"],
            keywords: ["uppercase", "lowercase", "title case", "trim", "sort lines"],
            examples: ["Convert this to title case", "Trim whitespace from this text"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Transform text using the compiled Text Studio Core.",
            parameters: NativeToolSchema.object(
                properties: [
                    "text": NativeToolSchema.string(description: "Text to transform."),
                    "transform": NativeToolSchema.string(
                        description: "Transformation to apply.",
                        enumValues: NativeAppTextStudioTransform.allCases.map(\.rawValue)
                    )
                ],
                required: ["text", "transform"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let text = NativeAppJSON.string(object, "text")
        let rawTransform = NativeAppJSON.string(object, "transform")
        guard !text.isEmpty else { return NativeToolResult(modelText: "Missing text to transform.") }
        guard let transform = NativeAppTextStudioTransform(rawValue: rawTransform) else {
            return NativeToolResult(modelText: "Unknown text transformation: \(rawTransform)")
        }
        let output = service.transform(text, using: transform)
        return NativeToolResult(
            modelText: "Transformed text (\(transform.rawValue)):\n\(output)",
            userText: output,
            uiBlocks: [
                NativeUIBlock(
                    type: .card,
                    title: transform.title,
                    body: output,
                    systemImage: "wand.and.stars",
                    actions: [
                        NativeUIAction(type: .copyText, title: "Copy Result", systemImage: "doc.on.doc", text: output),
                        NativeUIAction(
                            type: .openAppRoute,
                            title: "Open Transform in Text Studio",
                            systemImage: "arrow.up.forward.app",
                            route: .textStudioTransform(text: output, transform: transform.rawValue),
                            presentationStyle: .fullScreen
                        )
                    ]
                )
            ]
        )
    }
}
