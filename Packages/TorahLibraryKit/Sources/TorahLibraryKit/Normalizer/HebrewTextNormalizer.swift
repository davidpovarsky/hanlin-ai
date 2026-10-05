import Foundation

public struct NormalizedMapping: Sendable {
    public let rawText: String
    public let normalizedText: String
    public let normalizedToRawIndices: [Int]

    public init(rawText: String, normalizedText: String, normalizedToRawIndices: [Int]) {
        self.rawText = rawText
        self.normalizedText = normalizedText
        self.normalizedToRawIndices = normalizedToRawIndices
    }

    public func rawOffset(for normalizedOffset: Int) -> Int {
        guard !normalizedToRawIndices.isEmpty else { return 0 }
        let clamped = max(0, min(normalizedOffset, normalizedToRawIndices.count - 1))
        return normalizedToRawIndices[clamped]
    }
}

public enum HebrewTextNormalizer {
    /// Strips Hebrew vocalization (niqqud) and cantillation (teamim) while recording index mappings.
    public static func normalize(text: String, preserveGershayim: Bool = true, canonicalizeFinals: Bool = false) -> NormalizedMapping {
        var normalizedScalars: [UnicodeScalar] = []
        var mapping: [Int] = []

        let rawScalars = Array(text.unicodeScalars)
        for (rawIdx, scalar) in rawScalars.enumerated() {
            // Check if this scalar is a Hebrew diacritic (U+0591 to U+05AF teamim, U+05B0 to U+05BD niqqud, U+05BF, U+05C1-U+05C7)
            let isDiacritic = (scalar.value >= 0x0591 && scalar.value <= 0x05BD) ||
                scalar.value == 0x05BF ||
                (scalar.value >= 0x05C1 && scalar.value <= 0x05C7)

            if isDiacritic {
                continue
            }

            let char = Character(scalar)
            // Normalize quotes and gershayim
            if !preserveGershayim && (char == "״" || char == "\"" || char == "”" || char == "“") {
                continue
            }
            if !preserveGershayim && (char == "׳" || char == "'" || char == "’" || char == "`") {
                continue
            }

            // Canonicalize whitespace
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if let last = normalizedScalars.last, CharacterSet.whitespaces.contains(last) {
                    continue
                }
                normalizedScalars.append(UnicodeScalar(0x0020)!) // space
                mapping.append(rawIdx)
                continue
            }

            // Final Hebrew letters mapping if requested
            let canonicalChar = canonicalizeFinals ? canonicalHebrewChar(char) : char
            if let firstScalar = canonicalChar.unicodeScalars.first {
                normalizedScalars.append(firstScalar)
            } else {
                normalizedScalars.append(scalar)
            }
            mapping.append(rawIdx)
        }

        var normalizedStr = String(String.UnicodeScalarView(normalizedScalars))
        normalizedStr = normalizedStr.trimmingCharacters(in: .whitespaces)
        return NormalizedMapping(
            rawText: text,
            normalizedText: normalizedStr,
            normalizedToRawIndices: mapping
        )
    }

    /// Strips niqqud without tracking indices.
    public static func stripNiqqud(from text: String) -> String {
        normalize(text: text).normalizedText
    }

    /// Maps final Hebrew letters to regular letters if requested for fuzzy match.
    public static func canonicalHebrewChar(_ char: Character) -> Character {
        switch char {
        case "ך": return "כ"
        case "ם": return "מ"
        case "ן": return "נ"
        case "ף": return "פ"
        case "ץ": return "צ"
        case "״", "”", "“": return "\""
        case "׳", "’", "`": return "'"
        default: return char
        }
    }

    /// Extracts search anchors (sequences of significant words, excluding single characters).
    public static func extractAnchors(from text: String, minWordLength: Int = 3, anchorSize: Int = 3) -> [String] {
        let normalized = stripNiqqud(from: text)
        let words = normalized.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { $0.count >= minWordLength }

        guard words.count >= anchorSize else {
            return [words.joined(separator: " ")].filter { !$0.isEmpty }
        }

        var anchors: [String] = []
        for i in 0...(words.count - anchorSize) {
            let anchor = words[i..<(i + anchorSize)].joined(separator: " ")
            anchors.append(anchor)
        }
        return anchors
    }
}
