//
//  WebSearchRelevanceEvaluator.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Evaluates search result topical relevance and filters out obvious off-topic or spam results.
public struct WebSearchRelevanceEvaluator: Sendable {

    // Stopwords for English and Hebrew
    private static let englishStopwords: Set<String> = [
        "the", "a", "an", "and", "or", "in", "on", "at", "to", "for", "of", "with",
        "by", "is", "are", "was", "were", "be", "this", "that", "it", "from", "as"
    ]

    private static let hebrewStopwords: Set<String> = [
        "של", "על", "את", "עם", "כי", "כל", "זה", "זו", "אם", "או", "גם", "מה",
        "מי", "הוא", "היא", "הם", "הן", "בין", "רק", "עוד", "שם", "לא", "כן",
        "יותר", "אחרי", "לפני", "כמו", "אבל"
    ]

    // Specific domain intent indicators for mismatch detection
    private static let prayerTorahKeywords: Set<String> = [
        "תפילה", "זמני", "זמנים", "הלכה", "הלכתיים", "פרשת", "פרשה", "רש\"י", "רשי",
        "משנה", "גמרא", "שבת", "שחרית", "מנחה", "ערבית", "חב\"ד", "ירושלים", "תורה"
    ]

    private static let commercialHotelKeywords: Set<String> = [
        "hotel", "hotels", "מלון", "מלונות", "booking", "resort", "resorts",
        "vacation", "suite", "hostel", "accommodation"
    ]

    private static let developerKeywords: Set<String> = [
        "swiftui", "swift", "ios", "xcode", "apple", "uikit", "developer", "sdk", "api"
    ]

    private static let boardGameKeywords: Set<String> = [
        "card game", "bridge game", "trick-taking", "trump card"
    ]

    public init() {}

    /// Strips Hebrew niqqud (points/vowels) and cantillation marks (U+0591...U+05C7),
    /// which Foundation's standard `.diacriticInsensitive` comparison does not remove.
    public static func stripHebrewDiacritics(from text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !(0x0591...0x05C7).contains($0.value) }))
    }

    /// Normalizes text for linguistic relevance evaluation:
    /// case/diacritic folded, Hebrew niqqud stripped.
    public static func normalizeText(_ text: String) -> String {
        let noNiqqud = stripHebrewDiacritics(from: text)
        return noNiqqud.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Extracts significant query tokens (length >= 2, non-stopword).
    public static func extractTokens(from query: String) -> [String] {
        let cleanQuery = normalizeText(query)
        var tokens = cleanQuery.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        // Also extract gershayim-stripped variants (e.g. רש"י -> רשי)
        let gershayimStripped = cleanQuery
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "״", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "׳", with: "")
        let unquotedTokens = gershayimStripped.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        for tok in unquotedTokens where !tokens.contains(tok) {
            tokens.append(tok)
        }

        return tokens.filter { token in
            let lower = token.lowercased()
            return !englishStopwords.contains(lower) && !hebrewStopwords.contains(lower)
        }
    }

    /// Checks whether an individual result is topically relevant to query tokens.
    public static func isResultRelevant(_ result: WebSearchResult, queryTokens: [String], query: String) -> Bool {
        guard result.isValid else { return false }

        let lowerQuery = normalizeText(query)
        let combinedRaw = "\(result.title) \(result.snippet)"
        let combinedText = normalizeText(combinedRaw)
        let combinedUnquoted = combinedText
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "״", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "׳", with: "")

        // 1. Check for explicit intent mismatch: e.g. Torah/Prayer query returning purely hotels
        let isPrayerQuery = prayerTorahKeywords.contains { lowerQuery.contains($0) }
        if isPrayerQuery {
            let hasPrayerMatch = prayerTorahKeywords.contains { combinedText.contains($0) || combinedUnquoted.contains($0) }
            let hasHotelKeywords = commercialHotelKeywords.contains { combinedText.contains($0) }
            if hasHotelKeywords && !hasPrayerMatch {
                return false // Reject hotel spam masquerading as prayer times
            }
        }

        // 2. Check for technical mismatch: e.g. SwiftUI query returning card game bridge
        let isDevQuery = developerKeywords.contains { lowerQuery.contains($0) }
        if isDevQuery {
            let hasBoardGame = boardGameKeywords.contains { combinedText.contains($0) }
            let hasDevMatch = developerKeywords.contains { combinedText.contains($0) }
            if hasBoardGame && !hasDevMatch {
                return false
            }
        }

        // 3. Token match: at least one significant token must appear in title or snippet
        if queryTokens.isEmpty {
            return true
        }

        let hasTokenMatch = queryTokens.contains { token in
            let lower = token.lowercased()
            return combinedText.contains(lower) || combinedUnquoted.contains(lower)
        }
        return hasTokenMatch
    }

    /// Evaluates a collection of results against the query.
    /// Returns the filtered relevant results, or empty if the overall result set fails quality threshold.
    public static func evaluate(results: [WebSearchResult], for query: String) -> [WebSearchResult] {
        let tokens = extractTokens(from: query)
        guard !results.isEmpty else { return [] }

        let relevant = results.filter { isResultRelevant($0, queryTokens: tokens, query: query) }

        // Quality threshold: at least 1 result must be relevant,
        // and if 3+ results returned, at least 30% must be topically relevant.
        if relevant.isEmpty {
            return []
        }
        let relevanceRatio = Double(relevant.count) / Double(results.count)
        if results.count >= 3 && relevanceRatio < 0.3 {
            return []
        }

        return relevant
    }
}
