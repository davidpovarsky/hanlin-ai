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

    public static let modelInstructions = """
    When an answer uses a retrieved web source, place its citation immediately after the supported sentence's ending punctuation as [source](EXACT_SOURCE_URL). Use only URLs actually supplied by the tool or retrieved material. Put multiple relevant source links together after the same sentence. Do not invent URLs, cite unrelated sources, or use bare numeric [index] markers. Keep ordinary links that are part of your prose. The app presents these source links as grouped inline citations and provides the final source list; do not add a duplicate Sources section.
    """

    /// Uses the original Markdown renderer's CitationCoder contract. The answer
    /// remains ordinary Markdown; no parallel paragraph/selection renderer exists.
    public static func make(text: String, messageID: UUID, sources: [HanlinSourceReference],
                            anchors: [HanlinCitationAnchor], namespace: String = "answer") -> Self {
        let value = text as NSString
        let units = Array(text.utf16)
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let excluded = excludedMarkdownRanges(text)
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
            // Different ordered Markdown parts can have the same local offset.
            // Their links must never open a sibling part's source list.
            let id = "\(namespace):sentence-\(offset)"
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

    /// An assistant's explicit source link after sentence punctuation is a
    /// claim anchor too. This is how tool-using Chat Completions providers cite
    /// sources; they do not emit OpenAI Responses annotation events. Only an
    /// exact URL already present in the host's returned evidence is admitted.
    /// Ordinary prose links, images, code and bare [1] markers stay untouched.
    public static func explicitSourceLinkAnchors(text: String,
                                                sources: [HanlinSourceReference]) -> [HanlinCitationAnchor] {
        let excluded = excludedMarkdownRanges(text)
        let value = text as NSString
        let units = Array(text.utf16)
        guard let regex = try? NSRegularExpression(pattern:
            #"(?<!!)\[[^\]\n]*\]\((?:<https?://[^>\s]+>|https?://(?:[^\s()\\]|\\.|\([^\s()]*\))+)\)"#) else { return [] }
        var known: [(range: NSRange, sourceID: String)] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: value.length)) {
            let start = match.range.location
            guard !excluded.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                  !isEscaped(start, in: units),
                  let destination = sourceLinkURL(value.substring(with: match.range)),
                  hasCitationLabel(value.substring(with: match.range), url: destination),
                  let source = sources.first(where: { $0.url == destination }) else { continue }
            known.append((match.range, source.id))
        }
        var withoutLinks = units
        for match in known {
            for index in match.range.location..<NSMaxRange(match.range) { withoutLinks[index] = 32 }
        }
        return known.compactMap { match in
            // Do not turn a linked noun in the middle of a sentence into a
            // source badge: that would remove actual answer content.
            guard precedingSentenceEnd(withoutLinks, before: match.range.location) != nil else { return nil }
            return .init(sourceID: match.sourceID,
                         range: match.range.location..<NSMaxRange(match.range))
        }
    }

    private static func originalLink(_ text: String, pointsTo url: URL) -> Bool {
        sourceLinkURL(text) == url
    }

    private static func hasCitationLabel(_ text: String, url: URL) -> Bool {
        guard let delimiter = text.range(of: "](") else { return false }
        let label = text[text.index(after: text.startIndex)..<delimiter.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceLabels: Set<String> = ["source", "sources", "reference", "references", "ref",
            "מקור", "מקורות", "المصدر", "مصدر", "来源", "出典"]
        return sourceLabels.contains(label) || (!label.isEmpty && label.allSatisfy(\.isNumber))
            || label == url.host?.lowercased()
    }

    private static func sourceLinkURL(_ text: String) -> URL? {
        guard text.first == "[", text.last == ")", let delimiter = text.range(of: "](") else { return nil }
        var destination = String(text[delimiter.upperBound..<text.index(before: text.endIndex)])
        if destination.first == "<", destination.last == ">" { destination = String(destination.dropFirst().dropLast()) }
        destination = destination.replacingOccurrences(of: #"\("#, with: "(")
            .replacingOccurrences(of: #"\)"#, with: ")")
        guard let url = URL(string: destination), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func isEscaped(_ offset: Int, in units: [UInt16]) -> Bool {
        var index = offset - 1, count = 0
        while index >= 0, units[index] == 92 { count += 1; index -= 1 }
        return !count.isMultiple(of: 2)
    }

    private static func precedingSentenceEnd(_ text: [UInt16], before offset: Int) -> Int? {
        let terminals = Set(".!?。！？؟׃".utf16)
        let closers = Set("\"'”’)]}*_".utf16)
        var index = offset - 1
        while index >= 0, text[index] == 32 || text[index] == 9 || closers.contains(text[index]) { index -= 1 }
        guard index >= 0, terminals.contains(text[index]) else { return nil }
        var end = index + 1
        while end < text.count, closers.contains(text[end]) { end += 1 }
        return end
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
        if let boundary = precedingSentenceEnd(text, before: offset) { return boundary }
        var position = offset
        while position < text.count {
            if text[position] == 10 || text[position] == 13 || text[position] == 96 { return nil }
            if let boundary = end(after: position) { return boundary }
            position += 1
        }
        return nil
    }

    private static func excludedMarkdownRanges(_ text: String) -> [NSRange] {
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
        // The host is recognizing citation tokens, not rendering Markdown.
        // Keep inline code opaque to that recognition as the real parser does.
        let units = Array(text.utf16)
        var cursor = 0
        while cursor < units.count {
            guard units[cursor] == 96, !isEscaped(cursor, in: units),
                  !result.contains(where: { NSLocationInRange(cursor, $0) }) else { cursor += 1; continue }
            let start = cursor
            while cursor < units.count, units[cursor] == 96 { cursor += 1 }
            let delimiterLength = cursor - start
            var probe = cursor, matched = false
            while probe < units.count {
                guard units[probe] == 96 else { probe += 1; continue }
                let closingStart = probe
                while probe < units.count, units[probe] == 96 { probe += 1 }
                if probe - closingStart == delimiterLength {
                    result.append(NSRange(location: start, length: probe - start))
                    cursor = probe; matched = true; break
                }
            }
            if !matched { cursor = start + delimiterLength }
        }
        return result
    }
}
