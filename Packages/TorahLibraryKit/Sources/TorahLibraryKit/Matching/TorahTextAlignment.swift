import Foundation

public enum TorahTextAlignment {
    public struct AlignmentResult: Sendable {
        public let spans: [AlignmentSpan]
        public let scoreComponents: ScoreComponents
        public let overallScore: Double

        public init(spans: [AlignmentSpan], scoreComponents: ScoreComponents, overallScore: Double) {
            self.spans = spans
            self.scoreComponents = scoreComponents
            self.overallScore = overallScore
        }
    }

    /// Computes alignment between OCR lines and source text using token matching and sequence continuity.
    public static func align(ocrLines: [OCRLine], sourceText: String) -> AlignmentResult {
        guard !ocrLines.isEmpty, !sourceText.isEmpty else {
            return AlignmentResult(
                spans: [],
                scoreComponents: ScoreComponents(lexicalCoverage: 0, sequenceOrderScore: 0, boundaryMatchScore: 0, anchorUniqueness: 0),
                overallScore: 0
            )
        }

        let normalizedSource = HebrewTextNormalizer.normalize(text: sourceText, preserveGershayim: false)
        let sourceWords = normalizedSource.normalizedText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var totalOcrWords = 0
        var matchedOcrWords = 0
        var spans: [AlignmentSpan] = []
        var lastSourceIndex = -1
        var inOrderCount = 0

        for (lineIdx, line) in ocrLines.enumerated() {
            let normalizedLine = HebrewTextNormalizer.normalize(text: line.rawText, preserveGershayim: false)
            let lineWords = normalizedLine.normalizedText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            totalOcrWords += lineWords.count

            for word in lineWords {
                guard word.count >= 2 else { continue }
                if let srcIdx = sourceWords.firstIndex(where: { wordMatches($0, word) }) {
                    matchedOcrWords += 1
                    if srcIdx > lastSourceIndex {
                        inOrderCount += 1
                    }
                    lastSourceIndex = srcIdx

                    let span = AlignmentSpan(
                        ocrLineIndex: lineIdx,
                        ocrStartChar: 0,
                        ocrEndChar: line.rawText.count,
                        sourceStartChar: 0,
                        sourceEndChar: sourceText.count,
                        matchQuality: 0.95
                    )
                    spans.append(span)
                }
            }
        }

        let coverage = totalOcrWords > 0 ? Double(matchedOcrWords) / Double(totalOcrWords) : 0
        let orderScore = matchedOcrWords > 0 ? Double(inOrderCount) / Double(matchedOcrWords) : 0
        let boundaryScore = coverage > 0.8 ? 0.9 : 0.6
        let uniqueness = coverage > 0.7 ? 0.9 : 0.5

        let components = ScoreComponents(
            lexicalCoverage: coverage,
            sequenceOrderScore: orderScore,
            boundaryMatchScore: boundaryScore,
            anchorUniqueness: uniqueness
        )

        // Weighted overall score
        let overall = (coverage * 0.5) + (orderScore * 0.3) + (boundaryScore * 0.1) + (uniqueness * 0.1)

        return AlignmentResult(spans: spans, scoreComponents: components, overallScore: min(1.0, overall))
    }

    private static func wordMatches(_ w1: String, _ w2: String) -> Bool {
        if w1 == w2 { return true }
        // Allow 1 letter edit difference for words >= 4 letters
        if abs(w1.count - w2.count) <= 1 && min(w1.count, w2.count) >= 4 {
            return levenshteinDistance(w1, w2) <= 1
        }
        return false
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1)
                }
            }
        }
        return dist[a.count][b.count]
    }
}
