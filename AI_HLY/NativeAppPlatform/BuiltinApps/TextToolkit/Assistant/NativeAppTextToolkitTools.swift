import Foundation

struct NativeAppTextAnalyzeTool: NativeTool {
    let service: TextToolkitService
    let name = "app_text_analyze"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Text Toolkit Analyze",
            summary: "Analyze text length, words, sentences, lines, and links using the Text Toolkit native app.",
            categories: ["text", "utility", "native app"],
            keywords: ["word count", "characters", "links", "text analysis"],
            examples: ["Analyze this pasted text", "Count words and links"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Analyze text using the compiled Text Toolkit native app module.",
            parameters: NativeToolSchema.object(
                properties: ["text": NativeToolSchema.string(description: "Text to analyze.")],
                required: ["text"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let text = NativeAppJSON.string(object, "text")
        let analysis = service.analyze(text)
        let keyValues = [
            NativeUIKeyValue(key: "Characters", value: String(analysis.characters)),
            NativeUIKeyValue(key: "Words", value: String(analysis.words)),
            NativeUIKeyValue(key: "Sentences", value: String(analysis.sentences)),
            NativeUIKeyValue(key: "Lines", value: String(analysis.lines)),
            NativeUIKeyValue(key: "Links", value: String(analysis.links.count))
        ]
        let modelText = "Text analysis: characters=\(analysis.characters), words=\(analysis.words), sentences=\(analysis.sentences), lines=\(analysis.lines), links=\(analysis.links.count)."
        return NativeToolResult(
            modelText: modelText,
            uiBlocks: [NativeUIBlock(type: .keyValueList, title: "Text analysis", keyValues: keyValues)]
        )
    }
}

struct NativeAppTextTransformTool: NativeTool {
    let service: TextToolkitService
    let name = "app_text_transform"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Text Toolkit Transform",
            summary: "Transform text using the Text Toolkit native app core.",
            categories: ["text", "utility", "native app"],
            keywords: ["uppercase", "lowercase", "title case", "trim", "spaces"],
            examples: ["Convert this text to title case", "Remove extra spaces"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Transform text using the compiled Text Toolkit native app module.",
            parameters: NativeToolSchema.object(
                properties: [
                    "text": NativeToolSchema.string(description: "Text to transform."),
                    "transform": NativeToolSchema.string(description: "Transformation to apply.", enumValues: TextToolkitTransform.allCases.map(\.rawValue))
                ],
                required: ["text", "transform"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let text = NativeAppJSON.string(object, "text")
        let rawTransform = NativeAppJSON.string(object, "transform", default: TextToolkitTransform.removeExtraSpaces.rawValue)
        let transform = TextToolkitTransform(rawValue: rawTransform) ?? .removeExtraSpaces
        let output = service.transform(text, transform: transform)
        return NativeToolResult(
            modelText: output,
            userText: "Transformed text with \(transform.title).",
            uiBlocks: [
                NativeUIBlock(
                    type: .card,
                    title: "Text transform",
                    subtitle: transform.title,
                    body: output,
                    actions: [NativeUIAction(type: .copyText, title: "Copy", systemImage: "doc.on.doc", text: output)]
                )
            ]
        )
    }
}
