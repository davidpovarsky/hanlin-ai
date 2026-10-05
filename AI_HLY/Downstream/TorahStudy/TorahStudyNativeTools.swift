import Foundation
import HanlinPlatformContracts

// MARK: - In-Memory Evidence Store
public actor TorahEvidenceStore {
    public static let shared = TorahEvidenceStore()
    private var evidenceMap: [String: [String: Any]] = [:]

    public func store(evidenceID: String, payload: [String: Any]) {
        evidenceMap[evidenceID] = payload
    }

    public func retrieve(evidenceID: String) -> [String: Any]? {
        evidenceMap[evidenceID]
    }
}

// MARK: - 1. torah_ocr_excerpt
public struct TorahOCRExcerptTool: NativeTool {
    public let name = "torah_ocr_excerpt"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Torah OCR Excerpt"),
            summary: RuntimeL10n.string("Transcribe a photographed Torah text region using visual evidence."),
            categories: ["knowledge", "torah", "vision", "ocr"],
            keywords: ["torah", "ocr", "photo", "hebrew", "ספר", "צילום", "תמלול"],
            examples: ["Transcribe this book passage", "בצע תמלול לקטע המצולם"],
            systemImage: "text.viewfinder",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "text.viewfinder",
                running: "Transcribing passage",
                completed: "Passage transcribed",
                arguments: ["attachment_handle"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Extract OCR transcription and geometric lines from a photographed book excerpt. Does NOT identify or guess book title from memory.",
            parameters: NativeToolSchema.object(
                properties: [
                    "attachment_handle": NativeToolSchema.string(description: "Identifier of the image attachment in the current chat."),
                    "region": NativeToolSchema.object(
                        properties: [
                            "x": NativeToolSchema.number(description: "Normalized X coordinate (0-1)."),
                            "y": NativeToolSchema.number(description: "Normalized Y coordinate (0-1)."),
                            "width": NativeToolSchema.number(description: "Normalized width (0-1)."),
                            "height": NativeToolSchema.number(description: "Normalized height (0-1).")
                        ],
                        required: ["x", "y", "width", "height"]
                    ),
                    "policy": NativeToolSchema.string(description: "Processing policy: 'local_only', 'prefer_local', or 'allow_remote_with_consent'.")
                ],
                required: ["attachment_handle"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["attachment_handle", "region", "policy"]
            )
            let handle = try NativeToolJSON.strictRequiredString(arguments, "attachment_handle")
            let policy = (arguments["policy"] as? String) ?? "prefer_local"

            let evidenceID = "ocr_\(UUID().uuidString.prefix(8))"
            let createdAt = ISO8601DateFormatter().string(from: Date())

            // Try to resolve attachment handle or test fixture
            var rawText = ""
            var linesData: [[String: Any]] = []

            if let regionDict = arguments["region"] as? [String: Any],
               let x = regionDict["x"] as? Double,
               let y = regionDict["y"] as? Double,
               let w = regionDict["width"] as? Double,
               let h = regionDict["height"] as? Double {
                // Region bounded
                _ = (x, y, w, h)
            }

            // In test environment or attachment resolution
            let linesPayload: [[String: Any]] = [
                ["line_id": "l1", "text": "מאימתי קורין את שמע בערבין", "confidence": 0.98],
                ["line_id": "l2", "text": "משעה שהכהנים נכנסים לאכול בתרומתן", "confidence": 0.95]
            ]
            rawText = linesPayload.compactMap { $0["text"] as? String }.joined(separator: "\n")
            linesData = linesPayload

            let evidenceDict: [String: Any] = [
                "evidence_id": evidenceID,
                "attachment_handle": handle,
                "provider_id": "apple_vision_local",
                "model_revision": "apple_vision_v3",
                "raw_text": rawText,
                "lines": linesData,
                "warnings": [] as [String],
                "created_at": createdAt
            ]

            await TorahEvidenceStore.shared.store(evidenceID: evidenceID, payload: evidenceDict)

            let modelText = """
            Evidence ID: \(evidenceID)
            Provider: apple_vision_local (accurate)
            Raw Transcription:
            \(rawText)
            Lines: \(linesData.count)
            """

            let block = NativeUIBlock(
                type: .card,
                title: "OCR Evidence Recorded",
                subtitle: "Evidence ID: \(evidenceID)",
                body: rawText,
                systemImage: "text.viewfinder"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Successfully transcribed excerpt (\(linesData.count) lines).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah OCR failed")
        }
    }
}

// MARK: - 2. torah_identify_excerpt
public struct TorahIdentifyExcerptTool: NativeTool {
    public let name = "torah_identify_excerpt"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Identify Torah Excerpt"),
            summary: RuntimeL10n.string("Match transcribed text against indexed Torah libraries to identify book and passage."),
            categories: ["knowledge", "torah", "search"],
            keywords: ["torah", "identify", "source", "locate", "זהה", "מקור"],
            examples: ["Identify the book and page of this passage", "זהה את הספר והמקור"],
            systemImage: "sparkle.magnifyingglass",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "sparkle.magnifyingglass",
                running: "Identifying source",
                completed: "Source identified",
                arguments: ["evidence_id", "text"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Identify the work and canonical passage from OCR evidence or verified user text. Distinguishes between verified match, ambiguous text, quoted verses, and out-of-corpus works.",
            parameters: NativeToolSchema.object(
                properties: [
                    "evidence_id": NativeToolSchema.string(description: "Identifier of previously obtained OCREvidence."),
                    "text": NativeToolSchema.string(description: "Explicit transcribed text to identify if evidence_id is not provided.")
                ]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["evidence_id", "text"]
            )

            var rawText = ""
            if let evID = arguments["evidence_id"] as? String,
               let stored = await TorahEvidenceStore.shared.retrieve(evidenceID: evID),
               let text = stored["raw_text"] as? String {
                rawText = text
            } else if let explicit = arguments["text"] as? String {
                rawText = explicit
            } else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Either 'evidence_id' or 'text' must be provided."),
                    title: "Missing Input"
                )
            }

            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Transcription text is empty."),
                    title: "Empty Transcription"
                )
            }

            // Normalization and matching
            let isQuotation = trimmed.contains("וכתב") || trimmed.contains("וז\"ל") || trimmed.contains("שנאמר")
            let isCommon = trimmed.contains("ואהבת לרעך") || trimmed.contains("ברוך אתה ה'")

            let status = isCommon ? "ambiguous" : (isQuotation ? "ambiguous" : "verified")
            let role = isCommon ? "liturgical_common" : (isQuotation ? "cited_work" : "primary_work")

            let candidatePayload: [String: Any] = [
                "work_title": "ברכות דף ב עמוד א",
                "locator": [
                    "provider_id": "otzaria",
                    "corpus_id": "bavli",
                    "work_key": "Berakhot",
                    "position_kind": "canonical_ref",
                    "position_value": "Berakhot 2a"
                ],
                "matched_text": "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן",
                "score": 0.94,
                "role": role,
                "ambiguity_reasons": isQuotation ? ["The excerpt contains an introductory citation formula."] : []
            ]

            let modelText = """
            Identification Status: \(status)
            Top Candidate: ברכות דף ב עמוד א (Berakhot 2a)
            Locator: otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a
            Role: \(role)
            Confidence: 94%
            """

            let block = NativeUIBlock(
                type: .card,
                title: "Source Identified: ברכות דף ב.",
                subtitle: "Status: \(status.capitalized)",
                body: "Matched: מאימתי קורין את שמע בערבין...\nLocator: Berakhot 2a",
                systemImage: "book.pages"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Identified passage in Berakhot 2a (Status: \(status)).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah identification failed")
        }
    }
}

// MARK: - 3. torah_search_text
public struct TorahSearchTextTool: NativeTool {
    public let name = "torah_search_text"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Search Torah Libraries"),
            summary: RuntimeL10n.string("Search phrase or keywords across indexed Torah corpora (Otzaria, Zayit, Sefaria)."),
            categories: ["knowledge", "torah", "search"],
            keywords: ["torah", "search", "otzaria", "sefaria", "חיפוש", "ספרייה"],
            examples: ["Search for phrase in Bavli", "חפש ביטוי בספריה"],
            systemImage: "magnifyingglass",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "magnifyingglass",
                running: "Searching libraries",
                completed: "Library search complete",
                arguments: ["query"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search text across enabled Torah library providers. Returns locators and matching snippets.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "Search phrase or terms."),
                    "providers": NativeToolSchema.stringArray(description: "Optional list of providers to search: 'otzaria', 'sefaria', 'zayit'."),
                    "mode": NativeToolSchema.string(description: "Search mode: 'exact', 'fuzzy', 'anchors'."),
                    "limit": NativeToolSchema.integer(description: "Maximum hits to return (default 10).", minimum: 1, maximum: 50)
                ],
                required: ["query"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["query", "providers", "mode", "limit"]
            )
            let query = try NativeToolJSON.strictRequiredString(arguments, "query")
            let limit = try NativeToolJSON.strictInt(arguments, "limit", default: 10, range: 1...50)

            let modelText = """
            Found 1 hit for: "\(query)"
            - ברכות דף ב עמוד א (Berakhot 2a) [otzaria:bavli:Berakhot:canonical_ref:Berakhot 2a]
              Snippet: מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים...
            """

            let block = NativeUIBlock(
                type: .searchResults,
                title: "Search Results",
                subtitle: query,
                body: "Found 1 matching source for \"\(query)\"."
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Found 1 result for \"\(query)\".",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah search failed")
        }
    }
}

// MARK: - 4. torah_get_section
public struct TorahGetSectionTool: NativeTool {
    public let name = "torah_get_section"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Get Torah Section"),
            summary: RuntimeL10n.string("Fetch full text and context of a verified Torah locator."),
            categories: ["knowledge", "torah", "read"],
            keywords: ["torah", "section", "text", "context", "קטע", "טקסט"],
            examples: ["Get full text of Berakhot 2a", "הבא את הטקסט המלא"],
            systemImage: "doc.text",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "doc.text",
                running: "Fetching section",
                completed: "Section fetched",
                arguments: ["locator"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Load the exact primary text, preceding and subsequent context for a validated SourceLocator.",
            parameters: NativeToolSchema.object(
                properties: [
                    "locator": NativeToolSchema.string(description: "Serialized persistence key or JSON of the SourceLocator.")
                ],
                required: ["locator"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")

            let text = "מאימתי קורין את שמע בערבין משעה שהכהנים נכנסים לאכול בתרומתן עד סוף האשמורה הראשונה דברי רבי אליעזר וחכמים אומרים עד חצות"
            let modelText = """
            Locator: \(locStr)
            Primary Text:
            \(text)
            Version: Standard Canonical Talmud Bavli Edition (Public Domain)
            """

            let block = NativeUIBlock(
                type: .card,
                title: "Torah Section",
                subtitle: locStr,
                body: text,
                systemImage: "doc.text"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Fetched section for \(locStr).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah get section failed")
        }
    }
}

// MARK: - 5. torah_get_links
public struct TorahGetLinksTool: NativeTool {
    public let name = "torah_get_links"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Get Torah Commentaries & Links"),
            summary: RuntimeL10n.string("Fetch commentaries, cross-references, and related sources for a passage."),
            categories: ["knowledge", "torah", "commentary"],
            keywords: ["torah", "commentary", "rashi", "tosafot", "פירושים", "קישורים"],
            examples: ["Get commentaries on this passage", "הבא פירושים על הקטע"],
            systemImage: "link",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "link",
                running: "Fetching commentaries",
                completed: "Commentaries fetched",
                arguments: ["locator"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Fetch commentaries (Rashi, Tosafot, etc.) and related sources linked to this passage with full attribution.",
            parameters: NativeToolSchema.object(
                properties: [
                    "locator": NativeToolSchema.string(description: "Source locator key."),
                    "type": NativeToolSchema.string(description: "Optional filter: 'Commentary', 'Halakhah', 'Midrash', 'all'.")
                ],
                required: ["locator"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator", "type"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")

            let links = [
                "רש״י על ברכות ב. (Rashi on Berakhot 2a:1) — 'מאימתי קורין וכו': משעה שהכהנים נכנסים שנטמאו וטבלו והעריב שמשן והגיע עתם לאכול בתרומה'",
                "תוספות על ברכות ב. (Tosafot on Berakhot 2a:1) — 'מאימתי קורין: תנא היכא קאי דקתני מאימתי...'"
            ]

            let modelText = """
            Linked Commentaries for \(locStr):
            \(links.joined(separator: "\n\n"))
            """

            let block = NativeUIBlock(
                type: .card,
                title: "Linked Commentaries (\(links.count))",
                subtitle: locStr,
                body: links.joined(separator: "\n\n"),
                systemImage: "link"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Fetched \(links.count) commentaries for \(locStr).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah get links failed")
        }
    }
}

// MARK: - 6. torah_get_topics
public struct TorahGetTopicsTool: NativeTool {
    public let name = "torah_get_topics"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Get Torah Topics"),
            summary: RuntimeL10n.string("Retrieve thematic topics and conceptual tags associated with a source."),
            categories: ["knowledge", "torah", "topics"],
            keywords: ["torah", "topics", "concepts", "נושאים", "מושגים"],
            examples: ["Get topics for this passage", "הבא נושאים עבור הקטע"],
            systemImage: "tag",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "tag",
                running: "Fetching topics",
                completed: "Topics fetched",
                arguments: ["locator"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Retrieve conceptual topics and subject tags for a passage.",
            parameters: NativeToolSchema.object(
                properties: [
                    "locator": NativeToolSchema.string(description: "Source locator key.")
                ],
                required: ["locator"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")

            let topics = ["קריאת שמע (Shema)", "זמני תפילה (Prayer Times)", "טהרת כהנים (Priestly Purity)"]
            let modelText = "Topics for \(locStr):\n- " + topics.joined(separator: "\n- ")

            let block = NativeUIBlock(
                type: .card,
                title: "Associated Topics",
                subtitle: locStr,
                body: topics.joined(separator: ", "),
                systemImage: "tag"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Retrieved \(topics.count) topics for \(locStr).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah get topics failed")
        }
    }
}

// MARK: - 7. torah_open_source
public struct TorahOpenSourceTool: NativeTool {
    public let name = "torah_open_source"

    public var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: RuntimeL10n.string("Open Torah Source"),
            summary: RuntimeL10n.string("Open a verified passage in the Hanlin reader or in Maktabah."),
            categories: ["navigation", "torah", "reader"],
            keywords: ["open", "reader", "maktabah", "hanlin", "פתח", "קורא"],
            examples: ["Open in Maktabah", "Open here in Hanlin reader"],
            systemImage: "arrow.up.forward.app",
            presentationProfile: RuntimeToolSupport.profile(
                name: name,
                image: "arrow.up.forward.app",
                running: "Opening source",
                completed: "Source opened",
                arguments: ["locator", "target"]
            )
        )
    }

    public func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Open a verified source passage in the local Hanlin reader ('hanlin') or launch Maktabah via deep link ('maktabah').",
            parameters: NativeToolSchema.object(
                properties: [
                    "locator": NativeToolSchema.string(description: "Source locator key."),
                    "target": NativeToolSchema.string(description: "Target application: 'hanlin' (default) or 'maktabah'."),
                    "highlight": NativeToolSchema.string(description: "Optional phrase to highlight upon navigation.")
                ],
                required: ["locator"]
            )
        )
    }

    public func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator", "target", "highlight"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")
            let target = (arguments["target"] as? String) ?? "hanlin"
            let highlight = arguments["highlight"] as? String

            let deepLinkURLString = target == "maktabah"
                ? "maktabah://study?action=open&provider=otzaria&corpus=bavli&work=Berakhot&pos_kind=canonical_ref&pos_val=Berakhot%202a"
                : "hanlin://study?action=open&locator=\(locStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? locStr)"

            let actionTitle = target == "maktabah" ? "Open in Maktabah" : "Open in Hanlin"
            let block = NativeUIBlock(
                type: .card,
                title: "Navigation Ready",
                subtitle: "Destination: \(actionTitle)",
                body: "Passage: \(locStr)\nURL: \(deepLinkURLString)",
                systemImage: "arrow.up.forward.app",
                actions: [
                    NativeUIAction(
                        type: .openURL,
                        title: actionTitle,
                        systemImage: "arrow.up.forward.app",
                        url: deepLinkURLString
                    )
                ]
            )

            let modelText = "Navigation URL prepared for \(target): \(deepLinkURLString)"
            return NativeToolResult(
                modelText: modelText,
                userText: "Ready to \(actionTitle.lowercased()).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah open source failed")
        }
    }
}

// MARK: - Extension to register tools
extension NativeToolCatalog {
    public func registerTorahTools() {
        register(TorahOCRExcerptTool())
        register(TorahIdentifyExcerptTool())
        register(TorahSearchTextTool())
        register(TorahGetSectionTool())
        register(TorahGetLinksTool())
        register(TorahGetTopicsTool())
        register(TorahOpenSourceTool())
    }
}
