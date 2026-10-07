import Foundation
import HanlinPlatformContracts
import TorahLibraryKit

// MARK: - In-Memory Evidence Store
struct TorahEvidenceRecord: Codable, Hashable, Sendable {
    let evidenceID: String
    let rawText: String
    let attachmentHandle: String?
    let providerID: String
    let createdAt: String
}

actor TorahEvidenceStore {
    static let shared = TorahEvidenceStore()
    private var evidenceMap: [String: TorahEvidenceRecord] = [:]

    func store(evidenceID: String, record: TorahEvidenceRecord) {
        evidenceMap[evidenceID] = record
    }

    func retrieve(evidenceID: String) -> TorahEvidenceRecord? {
        evidenceMap[evidenceID]
    }
}

// MARK: - 1. torah_ocr_excerpt
struct TorahOCRExcerptTool: NativeTool {
    let name = "torah_ocr_excerpt"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["attachment_handle", "region", "policy"]
            )
            let handle = try NativeToolJSON.strictRequiredString(arguments, "attachment_handle")
            let policy = (arguments["policy"] as? String) ?? "prefer_local"

            let evidenceID = "ocr_\(UUID().uuidString.prefix(8))"
            let createdAt = ISO8601DateFormatter().string(from: Date())

            // Resolve real image data from attachment_handle
            let imageData: Data
            if FileManager.default.fileExists(atPath: handle) {
                imageData = try Data(contentsOf: URL(fileURLWithPath: handle))
            } else if let url = URL(string: handle), url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                imageData = try Data(contentsOf: url)
            } else if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let candidate = appSupport.appendingPathComponent("Attachments").appendingPathComponent(handle)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    imageData = try Data(contentsOf: candidate)
                } else {
                    return RuntimeToolSupport.failure(
                        HanlinHostServiceError.invalidArguments("Unable to resolve image attachment handle '\(handle)': file not found."),
                        title: "Attachment Not Found"
                    )
                }
            } else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Unable to resolve image attachment handle '\(handle)': file not found."),
                    title: "Attachment Not Found"
                )
            }

            var regionTuple: (x: Double, y: Double, width: Double, height: Double)? = nil
            if let regionDict = arguments["region"] as? [String: Any],
               let x = regionDict["x"] as? Double,
               let y = regionDict["y"] as? Double,
               let w = regionDict["width"] as? Double,
               let h = regionDict["height"] as? Double {
                regionTuple = (x: x, y: y, width: w, height: h)
            }

            let ocrResult = try await TorahOCRService.performLocalOCR(imageData: imageData, region: regionTuple)
            let rawText = ocrResult.rawText
            let linesData: [[String: Any]] = ocrResult.lines.enumerated().map { (idx, item) in
                [
                    "line_id": "l\(idx + 1)",
                    "text": item.text,
                    "confidence": item.confidence,
                    "bounding_box": [
                        "x": item.box.x,
                        "y": item.box.y,
                        "width": item.box.width,
                        "height": item.box.height
                    ]
                ]
            }

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return RuntimeToolSupport.failure(
                    HanlinHostServiceError.invalidArguments("Local OCR produced empty text for attachment '\(handle)'."),
                    title: "OCR Produced No Text"
                )
            }

            let evidenceRecord = TorahEvidenceRecord(
                evidenceID: evidenceID,
                rawText: rawText,
                attachmentHandle: handle,
                providerID: "apple_vision_local",
                createdAt: createdAt
            )

            await TorahEvidenceStore.shared.store(evidenceID: evidenceID, record: evidenceRecord)

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
struct TorahIdentifyExcerptTool: NativeTool {
    let name = "torah_identify_excerpt"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["evidence_id", "text"]
            )

            var rawText = ""
            if let evID = arguments["evidence_id"] as? String,
               let stored = await TorahEvidenceStore.shared.retrieve(evidenceID: evID) {
                rawText = stored.rawText
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

            let evidenceLines = rawText.components(separatedBy: "\n").filter { !$0.isEmpty }.map {
                OCRLine(lineID: UUID().uuidString.prefix(6).description, rawText: $0, boundingBox: .full)
            }
            let ocrEvidence = OCREvidence(
                evidenceID: (arguments["evidence_id"] as? String) ?? "ev_\(UUID().uuidString.prefix(8))",
                imageHash: "img_\(UUID().uuidString.prefix(8))",
                imageWidth: 1024,
                imageHeight: 1400,
                providerID: "apple_vision_local",
                modelRevision: "v3",
                rawText: rawText,
                lines: evidenceLines
            )

            let identification = await TorahLibraryCoordinator.shared.identifyExcerpt(evidence: ocrEvidence)

            let statusStr = identification.status.rawValue
            if let top = identification.selectedCandidate {
                let roleStr = top.sourceRole.rawValue
                let scorePct = Int(top.overallScore * 100)
                let modelText = """
                Identification Status: \(statusStr)
                Top Candidate: \(top.workTitle)
                Locator: \(top.locator.persistenceKey)
                Role: \(roleStr)
                Confidence: \(scorePct)%
                Lexical Coverage: \(Int(top.scoreComponents.lexicalCoverage * 100))%
                Sequence Order: \(Int(top.scoreComponents.sequenceOrderScore * 100))%
                """

                let block = NativeUIBlock(
                    type: .card,
                    title: "Source Identified: \(top.workTitle)",
                    subtitle: "Status: \(statusStr.capitalized)",
                    body: "Matched: \(top.matchedSourceText.prefix(120))...\nLocator: \(top.locator.positionValue)",
                    systemImage: "book.pages"
                )

                return NativeToolResult(
                    modelText: modelText,
                    userText: "Identified passage in \(top.workTitle) (Status: \(statusStr)).",
                    uiBlocks: [block]
                )
            } else {
                let modelText = """
                Identification Status: \(statusStr)
                No matching passage found in enabled libraries.
                Warnings: \(identification.warnings.joined(separator: "; "))
                """

                let block = NativeUIBlock(
                    type: .card,
                    title: "Source Not Identified",
                    subtitle: "Status: \(statusStr.capitalized)",
                    body: identification.warnings.joined(separator: "\n"),
                    systemImage: "exclamationmark.triangle"
                )

                return NativeToolResult(
                    modelText: modelText,
                    userText: "Could not identify source from excerpt (Status: \(statusStr)).",
                    uiBlocks: [block]
                )
            }
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah identification failed")
        }
    }
}

// MARK: - 3. torah_search_text
struct TorahSearchTextTool: NativeTool {
    let name = "torah_search_text"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["query", "providers", "mode", "limit"]
            )
            let query = try NativeToolJSON.strictRequiredString(arguments, "query")
            let limit = try NativeToolJSON.strictInt(arguments, "limit", default: 10, range: 1...50)

            let providersList = (arguments["providers"] as? [String]) ?? []
            let mode = (arguments["mode"] as? String) ?? "exact"
            let hits = (try? await TorahLibraryCoordinator.shared.search(query: query, providers: providersList, mode: mode, limit: limit)) ?? []
            if hits.isEmpty {
                let modelText = "No hits found for: \"\(query)\" in enabled libraries."
                return NativeToolResult(modelText: modelText, userText: "No results found for \"\(query)\".")
            }

            let hitLines = hits.map { "- \($0.workTitle) [\($0.locator.persistenceKey)]\n  Snippet: \($0.textSnippet.prefix(120))..." }
            let modelText = "Found \(hits.count) hits for \"\(query)\":\n" + hitLines.joined(separator: "\n")
            let block = NativeUIBlock(
                type: .searchResults,
                title: "Search Results (\(hits.count))",
                subtitle: query,
                body: hitLines.joined(separator: "\n\n")
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Found \(hits.count) results for \"\(query)\".",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah search failed")
        }
    }
}

// MARK: - 4. torah_get_section
struct TorahGetSectionTool: NativeTool {
    let name = "torah_get_section"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")

            let locator: SourceLocator
            if let parsed = SourceLocator.parse(persistenceKey: locStr) {
                locator = parsed
            } else {
                locator = SourceLocator(
                    providerID: "sefaria",
                    corpusID: "canonical",
                    workKey: locStr,
                    positionKind: .canonicalRef,
                    positionValue: locStr
                )
            }

            let studySource = try? await TorahLibraryCoordinator.shared.getSection(locator: locator)
            let text = studySource?.primaryText ?? "Section text not available offline."
            let version = studySource?.versionMetadata.versionTitle ?? "Standard Canonical Edition"

            let modelText = """
            Locator: \(locStr)
            Primary Text:
            \(text)
            Version: \(version)
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
struct TorahGetLinksTool: NativeTool {
    let name = "torah_get_links"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator", "type"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")
            let filterType = arguments["type"] as? String

            let locator: SourceLocator
            if let parsed = SourceLocator.parse(persistenceKey: locStr) {
                locator = parsed
            } else {
                locator = SourceLocator(
                    providerID: "sefaria",
                    corpusID: "canonical",
                    workKey: locStr,
                    positionKind: .canonicalRef,
                    positionValue: locStr
                )
            }

            let linkedSources = (try? await TorahLibraryCoordinator.shared.getLinks(locator: locator, type: filterType)) ?? []
            let linkStrings: [String]
            if !linkedSources.isEmpty {
                linkStrings = linkedSources.map { "- \($0.sourceTitle) (\($0.category)): \($0.primaryText.prefix(120))..." }
            } else {
                linkStrings = ["No linked commentaries returned from provider."]
            }

            let modelText = """
            Linked Commentaries for \(locStr):
            \(linkStrings.joined(separator: "\n\n"))
            """

            let block = NativeUIBlock(
                type: .card,
                title: "Linked Commentaries (\(linkedSources.count))",
                subtitle: locStr,
                body: linkStrings.joined(separator: "\n\n"),
                systemImage: "link"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: "Fetched \(linkedSources.count) commentaries for \(locStr).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah get links failed")
        }
    }
}

// MARK: - 6. torah_get_topics
struct TorahGetTopicsTool: NativeTool {
    let name = "torah_get_topics"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")

            let locator: SourceLocator
            if let parsed = SourceLocator.parse(persistenceKey: locStr) {
                locator = parsed
            } else {
                locator = SourceLocator(
                    providerID: "otzaria",
                    corpusID: "canonical",
                    workKey: locStr,
                    positionKind: .canonicalRef,
                    positionValue: locStr
                )
            }

            let topicObjects = (try? await TorahLibraryCoordinator.shared.getTopics(locator: locator)) ?? []
            let topicNames = topicObjects.map { $0.topicTitle }

            let modelText: String
            let bodyText: String
            if !topicNames.isEmpty {
                modelText = "Topics for \(locStr):\n- " + topicNames.joined(separator: "\n- ")
                bodyText = topicNames.joined(separator: ", ")
            } else {
                modelText = "No thematic topics currently indexed for: \(locStr)."
                bodyText = "No thematic topics available for this passage."
            }

            let block = NativeUIBlock(
                type: .card,
                title: "Associated Topics (\(topicNames.count))",
                subtitle: locStr,
                body: bodyText,
                systemImage: "tag"
            )

            return NativeToolResult(
                modelText: modelText,
                userText: topicNames.isEmpty ? "No topics found for \(locStr)." : "Retrieved \(topicNames.count) topics for \(locStr).",
                uiBlocks: [block]
            )
        } catch {
            return RuntimeToolSupport.failure(error, title: "Torah get topics failed")
        }
    }
}

// MARK: - 7. torah_open_source
struct TorahOpenSourceTool: NativeTool {
    let name = "torah_open_source"

    var catalogEntry: NativeToolCatalogEntry {
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

    func openAIToolSchema() -> [String: Any] {
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

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.validatedDictionary(
                from: argumentsJSON,
                allowedKeys: ["locator", "target", "highlight"]
            )
            let locStr = try NativeToolJSON.strictRequiredString(arguments, "locator")
            let target = (arguments["target"] as? String) ?? "hanlin"
            let highlight = arguments["highlight"] as? String

            let locator: SourceLocator
            if let parsed = SourceLocator.parse(persistenceKey: locStr) {
                locator = parsed
            } else {
                locator = SourceLocator(
                    providerID: "otzaria",
                    corpusID: "canonical",
                    workKey: locStr,
                    positionKind: .canonicalRef,
                    positionValue: locStr
                )
            }

            let link = TorahStudyDeepLink(
                action: .open,
                locator: locator,
                workTitle: locator.workKey,
                highlightText: highlight
            )

            let scheme = target == "maktabah" ? "maktabah" : "hanlin"
            let deepLinkURLString = link.url(scheme: scheme)?.absoluteString ?? "\(scheme)://study?action=open&locator=\(locStr)"

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
    func registerTorahTools() {
        register(TorahOCRExcerptTool())
        register(TorahIdentifyExcerptTool())
        register(TorahSearchTextTool())
        register(TorahGetSectionTool())
        register(TorahGetLinksTool())
        register(TorahGetTopicsTool())
        register(TorahOpenSourceTool())
    }
}
