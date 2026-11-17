import Foundation

/// A value projection supplied by the host's existing source store.
public struct HanlinSourceReference: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let url: URL?
    public let iconURL: URL?
    public init(id: String, title: String, url: URL?, iconURL: URL? = nil) {
        self.id = id; self.title = title; self.url = url; self.iconURL = iconURL
    }
}

/// The host validates the original text identity and provider indexing convention
/// before passing this UTF-16 range. Source proximity never creates an anchor.
public struct HanlinCitationAnchor: Hashable, Sendable {
    public let sourceID: String
    public let range: Range<Int>
    public init(sourceID: String, range: Range<Int>) { self.sourceID = sourceID; self.range = range }
}

public struct HanlinCitationGroup: Hashable, Sendable, Identifiable {
    public let id: String
    public let url: URL
    public let sources: [HanlinSourceReference]
}

public struct HanlinCitationProjection: Sendable {
    public let markdown: String
    public let groups: [HanlinCitationGroup]

    /// Uses the original Markdown renderer's CitationCoder contract. The answer
    /// remains ordinary Markdown; no parallel paragraph/selection renderer exists.
    public static func make(text: String, messageID: UUID, sources: [HanlinSourceReference],
                            anchors: [HanlinCitationAnchor]) -> Self {
        let value = text as NSString
        let units = Array(text.utf16)
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let excluded = fencedRanges(text)
        var sentenceUnits = units
        for anchor in anchors.prefix(256) {
            guard let url = byID[anchor.sourceID]?.url, anchor.range.lowerBound >= 0,
                  anchor.range.upperBound <= units.count, !anchor.range.isEmpty,
                  Range(NSRange(anchor.range), in: text) != nil,
                  originalLink(value.substring(with: NSRange(anchor.range)), pointsTo: url) else { continue }
            for index in anchor.range { sentenceUnits[index] = 32 }
        }
        var grouped: [Int: [HanlinSourceReference]] = [:]
        var removals: Set<NSRange> = []
        for anchor in anchors.prefix(256) {
            guard let source = byID[anchor.sourceID], anchor.range.lowerBound >= 0,
                  anchor.range.upperBound > anchor.range.lowerBound, anchor.range.upperBound <= units.count,
                  Range(NSRange(anchor.range), in: text) != nil,
                  !excluded.contains(where: { NSIntersectionRange($0, NSRange(anchor.range)).length > 0 }) else { continue }
            let raw = value.substring(with: NSRange(anchor.range))
            let isOriginalLink = source.url.map { originalLink(raw, pointsTo: $0) } ?? false
            let searchFrom = isOriginalLink ? anchor.range.lowerBound : anchor.range.upperBound
            guard let boundary = sentenceEnd(sentenceUnits, from: searchFrom),
                  !excluded.contains(where: { NSLocationInRange(max(0, boundary - 1), $0) }) else { continue }
            if isOriginalLink { removals.insert(NSRange(anchor.range)) }
            if grouped[boundary]?.contains(where: { $0.id == source.id }) != true {
                grouped[boundary, default: []].append(source)
            }
        }
        var groups: [HanlinCitationGroup] = []
        var edits: [(range: NSRange, replacement: String)] = removals.map { ($0, "") }
        for offset in grouped.keys.sorted() {
            guard let references = grouped[offset], let first = references.first else { continue }
            let id = "sentence-\(offset)"
            let label = (first.url?.host ?? first.title) + (references.count > 1 ? " +\(references.count - 1)" : "")
            var url = URLComponents()
            url.scheme = "hanlin-citation"; url.host = messageID.uuidString.lowercased(); url.path = "/" + id
            url.queryItems = [
                .init(name: "citationMarker", value: "9F742443"),
                .init(name: "citationTitle", value: label),
                .init(name: "citationA11yValue", value: references.map(\.title).joined(separator: ", ")),
            ]
            guard let destination = url.url else { continue }
            groups.append(.init(id: id, url: destination, sources: references))
            edits.append((NSRange(location: offset, length: 0), " [9F742443](\(destination.absoluteString))"))
        }
        let output = NSMutableString(string: text)
        for edit in edits.sorted(by: {
            $0.range.location == $1.range.location ? $0.range.length > $1.range.length : $0.range.location > $1.range.location
        }) { output.replaceCharacters(in: edit.range, with: edit.replacement) }
        return .init(markdown: output as String, groups: groups)
    }

    private static func originalLink(_ text: String, pointsTo url: URL) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^\[[^\]\n]*\]\((https?://[^\s\)]+)\)$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return false }
        return URL(string: String(text[range])) == url
    }

    /// Hold a citation until punctuation completes its sentence. Never advance
    /// across a paragraph or into code, or attach a source to an unfinished line.
    private static func sentenceEnd(_ text: [UInt16], from offset: Int) -> Int? {
        let terminals = Set(".!?。！？؟׃".utf16)
        let closers = Set("\"'”’)]}*_".utf16)
        let space = Set(" \t\r\n".utf16)
        func end(after index: Int) -> Int? {
            guard index >= 0, index < text.count, terminals.contains(text[index]) else { return nil }
            var end = index + 1
            while end < text.count, closers.contains(text[end]) { end += 1 }
            return end == text.count || space.contains(text[end]) ? end : nil
        }
        var previous = offset - 1
        while previous >= 0, space.contains(text[previous]) || closers.contains(text[previous]) { previous -= 1 }
        if let boundary = end(after: previous) { return boundary }
        var position = offset
        while position < text.count {
            if text[position] == 10 || text[position] == 13 || text[position] == 96 { return nil }
            if let boundary = end(after: position) { return boundary }
            position += 1
        }
        return nil
    }

    private static func fencedRanges(_ text: String) -> [NSRange] {
        var result: [NSRange] = [], open: (marker: Character, length: Int, start: Int)?
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if let marker = trimmed.first, marker == "`" || marker == "~" {
                let length = trimmed.prefix(while: { $0 == marker }).count
                if length >= 3 {
                    if let current = open, current.marker == marker, length >= current.length {
                        result.append(NSRange(location: current.start, length: offset + line.utf16.count - current.start)); open = nil
                    } else if open == nil { open = (marker, length, offset) }
                }
            }
            offset += line.utf16.count + 1
        }
        if let open { result.append(NSRange(location: open.start, length: text.utf16.count - open.start)) }
        return result
    }
}
