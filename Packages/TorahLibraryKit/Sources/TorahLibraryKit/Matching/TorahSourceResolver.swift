import Foundation

public protocol TorahLibrarySearchEngine: Sendable {
    func search(anchors: [String], limit: Int) async throws -> [TorahSearchHit]
    func fetchSection(locator: SourceLocator) async throws -> String?
}

public struct TorahSearchHit: Sendable {
    public let locator: SourceLocator
    public let workTitle: String
    public let textSnippet: String
    public let fullText: String?
    public let providerScore: Double

    public init(
        locator: SourceLocator,
        workTitle: String,
        textSnippet: String,
        fullText: String? = nil,
        providerScore: Double = 1.0
    ) {
        self.locator = locator
        self.workTitle = workTitle
        self.textSnippet = textSnippet
        self.fullText = fullText
        self.providerScore = providerScore
    }
}

public actor TorahSourceResolver {
    private let searchEngines: [TorahLibrarySearchEngine]

    public init(searchEngines: [TorahLibrarySearchEngine] = []) {
        self.searchEngines = searchEngines
    }

    /// Resolves an OCR evidence into scored and classified excerpt candidates.
    public func resolve(evidence: OCREvidence, requestID: String = UUID().uuidString) async -> IdentificationResult {
        let raw = evidence.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        // Check for insufficient image / unreadable text
        if words.count < 3 {
            return IdentificationResult(
                status: .insufficientImage,
                candidates: [],
                warnings: ["The selected region contains insufficient text (fewer than 3 words) to reliably identify a source."],
                requestID: requestID
            )
        }

        // Extract anchors for multi-anchor search
        let anchors = HebrewTextNormalizer.extractAnchors(from: raw, minWordLength: 3, anchorSize: 3)
        guard !anchors.isEmpty else {
            return IdentificationResult(
                status: .insufficientImage,
                candidates: [],
                warnings: ["No search anchors could be extracted from the OCR text."],
                requestID: requestID
            )
        }

        var allHits: [TorahSearchHit] = []
        var searchedCorpora: [String] = []
        var unavailableCorpora: [String] = []

        for engine in searchEngines {
            do {
                let hits = try await engine.search(anchors: anchors, limit: 10)
                allHits.append(contentsOf: hits)
                searchedCorpora.append(String(describing: type(of: engine)))
            } catch {
                unavailableCorpora.append(String(describing: type(of: engine)))
            }
        }

        if allHits.isEmpty && !searchEngines.isEmpty {
            return IdentificationResult(
                status: unavailableCorpora.count == searchEngines.count ? .corpusUnavailable : .notFound,
                candidates: [],
                searchedCorpora: searchedCorpora,
                unavailableCorpora: unavailableCorpora,
                warnings: ["No matching passages were found in enabled libraries."],
                requestID: requestID
            )
        }

        // Align each candidate and calculate composite score
        var scoredCandidates: [ExcerptCandidate] = []
        let quotationDetected = containsQuotationIntro(raw)

        for hit in allHits {
            let fullText = hit.fullText ?? hit.textSnippet
            let alignment = TorahTextAlignment.align(ocrLines: evidence.lines, sourceText: fullText)

            var ambiguityReasons: [String] = []
            var sourceRole: SourceRole = .primaryWork

            // Check if this text is a common biblical or liturgical verse
            if isCommonBiblicalOrPrayer(raw) {
                ambiguityReasons.append("The photographed excerpt contains a widely repeated biblical or liturgical phrase found in many rabbinic works.")
                sourceRole = .liturgicalCommon
            } else if quotationDetected {
                ambiguityReasons.append("The excerpt contains quotation formulas indicating it may cite this work rather than being printed in it.")
                sourceRole = .citedWork
            }

            let candidate = ExcerptCandidate(
                locator: hit.locator,
                workTitle: hit.workTitle,
                matchedSourceText: fullText,
                alignment: alignment.spans,
                evidenceIDs: [evidence.evidenceID],
                scoreComponents: alignment.scoreComponents,
                overallScore: alignment.overallScore,
                ambiguityReasons: ambiguityReasons,
                retrievalMode: "lexical_anchor",
                sourceRole: sourceRole,
                physicalEditionStatus: .unknown
            )
            scoredCandidates.append(candidate)
        }

        // Sort descending by score
        scoredCandidates.sort { $0.overallScore > $1.overallScore }

        guard let top = scoredCandidates.first, top.overallScore >= 0.50 else {
            return IdentificationResult(
                status: .notFound,
                candidates: scoredCandidates,
                searchedCorpora: searchedCorpora,
                unavailableCorpora: unavailableCorpora,
                warnings: ["Top match score is below required identification threshold."],
                requestID: requestID
            )
        }

        // Check distinction between top candidate and second candidate
        let isAmbiguous: Bool
        if scoredCandidates.count > 1 {
            let second = scoredCandidates[1]
            let scoreDelta = top.overallScore - second.overallScore
            if scoreDelta < 0.12 && top.overallScore < 0.95 {
                isAmbiguous = true
            } else if !top.ambiguityReasons.isEmpty {
                isAmbiguous = true
            } else {
                isAmbiguous = false
            }
        } else {
            isAmbiguous = !top.ambiguityReasons.isEmpty
        }

        let finalStatus: IdentificationStatus
        if isAmbiguous {
            finalStatus = .ambiguous
        } else if top.overallScore >= 0.75 && top.scoreComponents.lexicalCoverage >= 0.65 {
            finalStatus = .verified
        } else {
            finalStatus = .ambiguous
        }

        return IdentificationResult(
            status: finalStatus,
            candidates: scoredCandidates,
            selectedCandidate: top,
            searchedCorpora: searchedCorpora,
            unavailableCorpora: unavailableCorpora,
            warnings: [],
            requestID: requestID
        )
    }

    private func containsQuotationIntro(_ text: String) -> Bool {
        let patterns = ["וכתב הרמב", "וז\"ל", "וזה לשונו", "ואיתא ב", "וכן כתב", "וכ\"כ", "אמר שמואל", "שנאמר", "כדכתיב"]
        return patterns.contains { text.contains($0) }
    }

    private func isCommonBiblicalOrPrayer(_ text: String) -> Bool {
        let common = ["ואהבת לרעך כמוך", "ברוך אתה ה", "מודה אני לפניך", "שמע ישראל ה", "הודו לה' כי טוב"]
        let normalized = HebrewTextNormalizer.stripNiqqud(from: text)
        return common.contains { normalized.contains($0) }
    }
}
