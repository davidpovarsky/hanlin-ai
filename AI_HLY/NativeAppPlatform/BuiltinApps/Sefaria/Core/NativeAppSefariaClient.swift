import Foundation

struct NativeAppSefariaClient {
    var baseURL = URL(string: "https://www.sefaria.org")!

    func search(query: String, limit: Int) async throws -> [NativeAppSefariaSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        NativeToolTraceLogger.shared.log(
            "sefaria_search_started",
            ["query": query, "normalizedQuery": normalizedQuery, "limit": limit]
        )

        let resolution = try await resolveName(normalizedQuery)
        if let resolvedRef = resolution.resolvedRef {
            let source = try await source(resolvedRef: resolvedRef)
            return [
                NativeAppSefariaSearchResult(
                    ref: source.ref,
                    title: source.ref,
                    snippet: Self.snippet(from: source.combinedText),
                    url: source.url
                )
            ]
        }

        let boundedLimit = max(1, min(limit, 20))
        let referenceCompletions = resolution.completions.filter { $0.ref != nil }
        let completions = referenceCompletions.isEmpty ? resolution.completions : referenceCompletions
        return completions.prefix(boundedLimit).map { completion in
            let ref = completion.ref ?? completion.title
            return NativeAppSefariaSearchResult(
                ref: ref,
                title: completion.title,
                snippet: completion.type.map {
                    String(format: String(localized: "Sefaria result type: %@"), $0)
                } ?? "",
                url: completion.url ?? Self.sefariaWebURL(for: ref, baseURL: baseURL)
            )
        }
    }

    func resolveName(_ query: String) async throws -> NativeAppSefariaNameResolution {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return NativeAppSefariaNameResolution(resolvedRef: nil, completions: [])
        }

        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("name")
            .appendingPathComponent(normalizedQuery)

        NativeToolTraceLogger.shared.log(
            "sefaria_name_resolution_requested",
            ["query": query, "normalizedQuery": normalizedQuery, "endpoint": url.absoluteString]
        )

        let json = try await requestJSON(url: url, endpoint: "api/name")
        let isReference = Self.bool(json["is_ref"])
        let topLevelType = Self.string(json["type"])?.lowercased()
        let resolvedRef: String?
        if isReference || topLevelType == "ref" {
            resolvedRef = Self.firstNonemptyString(
                json["ref"],
                json["key"],
                json["completion"],
                json["title"]
            )
        } else {
            resolvedRef = nil
        }

        let completions = Self.parseCompletions(json, baseURL: baseURL)
        NativeToolTraceLogger.shared.log(
            "sefaria_name_resolution_completed",
            [
                "query": query,
                "resolvedRef": resolvedRef as Any,
                "completionCount": completions.count,
                "isReference": isReference
            ]
        )
        return NativeAppSefariaNameResolution(resolvedRef: resolvedRef, completions: completions)
    }

    func source(ref: String) async throws -> NativeAppSefariaSource {
        let normalizedQuery = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { throw NativeAppSefariaError.invalidReference }
        let resolution = try await resolveName(normalizedQuery)
        guard let resolvedRef = resolution.resolvedRef else {
            throw NativeAppSefariaError.unresolvedReference(normalizedQuery)
        }
        return try await source(resolvedRef: resolvedRef)
    }

    private func source(resolvedRef: String) async throws -> NativeAppSefariaSource {
        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("v3")
                .appendingPathComponent("texts")
                .appendingPathComponent(resolvedRef.replacingOccurrences(of: " ", with: "_")),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "version", value: "hebrew"),
            URLQueryItem(name: "version", value: "english")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        NativeToolTraceLogger.shared.log(
            "sefaria_v3_text_requested",
            ["resolvedRef": resolvedRef, "endpoint": url.absoluteString]
        )
        let json: [String: Any]
        do {
            json = try await requestJSON(url: url, endpoint: "api/v3/texts")
        } catch {
            NativeToolTraceLogger.shared.logError(
                "sefaria_v3_text_failed",
                error: error,
                fields: ["resolvedRef": resolvedRef, "succeeded": false]
            )
            throw error
        }
        let versions = (json["versions"] as? [Any]) ?? []
        let candidates = versions.compactMap(Self.versionCandidate)
        let hebrew = Self.preferredVersion(in: candidates) { candidate in
            candidate.language == "he"
                || candidate.language == "hebrew"
                || candidate.languageFamily == "hebrew"
        }
        let english = Self.preferredVersion(in: candidates) { candidate in
            candidate.language == "en"
                || candidate.language == "english"
                || candidate.languageFamily == "english"
        }
        let fallback = Self.preferredVersion(in: candidates) { _ in true }

        let hebrewText = hebrew?.text
        let englishText = english?.text ?? (hebrewText == nil ? fallback?.text : nil)
        guard hebrewText != nil || englishText != nil else {
            throw NativeAppSefariaError.noText(resolvedRef)
        }

        let normalizedRef = Self.firstNonemptyString(json["ref"], json["title"]) ?? resolvedRef
        let source = NativeAppSefariaSource(
            ref: normalizedRef,
            text: englishText ?? "",
            heText: hebrewText,
            url: Self.sefariaWebURL(for: normalizedRef, baseURL: baseURL)
        )
        NativeToolTraceLogger.shared.log(
            "sefaria_v3_text_completed",
            [
                "resolvedRef": normalizedRef,
                "versionCount": versions.count,
                "foundHebrew": hebrewText != nil,
                "foundEnglish": englishText != nil,
                "hebrewVersionTitle": hebrew?.versionTitle as Any,
                "englishVersionTitle": english?.versionTitle as Any,
                "hebrewDirection": hebrew?.direction as Any,
                "englishDirection": english?.direction as Any,
                "returnedTextLength": source.combinedText.count,
                "succeeded": true
            ]
        )
        return source
    }

    private func requestJSON(url: URL, endpoint: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        NativeToolTraceLogger.shared.log(
            "sefaria_endpoint_response",
            ["endpoint": endpoint, "url": url.absoluteString, "statusCode": http.statusCode]
        )
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeAppSefariaError.invalidResponse
        }
        return json
    }

    private static func parseCompletions(
        _ json: [String: Any],
        baseURL: URL
    ) -> [NativeAppSefariaNameCompletion] {
        let rawObjects = (json["completion_objects"] as? [Any])
            ?? (json["objects"] as? [Any])
            ?? (json["refs"] as? [Any])
            ?? []
        let titles = stringArray(json["completions"])
        var completions = rawObjects.compactMap { value -> NativeAppSefariaNameCompletion? in
            if let title = string(value) {
                return NativeAppSefariaNameCompletion(
                    title: title,
                    ref: title,
                    type: "ref",
                    url: sefariaWebURL(for: title, baseURL: baseURL)
                )
            }
            guard let object = value as? [String: Any] else { return nil }
            let title = firstNonemptyString(object["title"], object["completion"], object["ref"], object["key"])
            guard let title else { return nil }
            let type = string(object["type"])
            let isReference = type?.lowercased() == "ref" || bool(object["is_ref"])
            let ref = isReference ? firstNonemptyString(object["ref"], object["key"], object["completion"], object["title"]) : nil
            let providedURL = string(object["url"]).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            let topicURL: URL? = type?.lowercased() == "topic"
                ? string(object["key"]).map { baseURL.appendingPathComponent("topics").appendingPathComponent($0) }
                : nil
            return NativeAppSefariaNameCompletion(
                title: title,
                ref: ref,
                type: type,
                url: providedURL ?? topicURL ?? ref.flatMap { sefariaWebURL(for: $0, baseURL: baseURL) }
            )
        }

        if completions.isEmpty {
            completions = titles.map { title in
                NativeAppSefariaNameCompletion(title: title, ref: title, type: nil, url: sefariaWebURL(for: title, baseURL: baseURL))
            }
        }

        var seen = Set<String>()
        return completions.filter { completion in
            let key = "\(completion.ref ?? "")|\(completion.title)"
            return seen.insert(key).inserted
        }
    }

    private static func versionCandidate(_ value: Any) -> VersionCandidate? {
        guard let version = value as? [String: Any],
              let rawText = flattenText(version["text"]) else { return nil }
        let text = clean(rawText)
        guard !text.isEmpty else { return nil }
        return VersionCandidate(
            language: string(version["language"])?.lowercased(),
            languageFamily: string(version["languageFamilyName"])?.lowercased(),
            text: text,
            isSource: bool(version["isSource"]),
            isPrimary: bool(version["isPrimary"]),
            priority: number(version["priority"]),
            versionTitle: string(version["versionTitle"]),
            direction: string(version["direction"])
        )
    }

    private static func preferredVersion(
        in candidates: [VersionCandidate],
        matching predicate: (VersionCandidate) -> Bool
    ) -> VersionCandidate? {
        candidates
            .filter(predicate)
            .sorted {
                if $0.preferenceScore != $1.preferenceScore {
                    return $0.preferenceScore > $1.preferenceScore
                }
                return $0.priority > $1.priority
            }
            .first
    }

    private static func flattenText(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            let values = array.compactMap { flattenText($0) }.filter { !$0.isEmpty }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { string($0) }.filter { !$0.isEmpty }
    }

    private static func firstNonemptyString(_ values: Any?...) -> String? {
        values.compactMap { string($0) }.first {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func bool(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["true", "1", "yes"].contains(string.lowercased()) }
        return false
    }

    private static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func snippet(from text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(singleLine.prefix(360))
    }

    private static func sefariaWebURL(for ref: String, baseURL: URL) -> URL? {
        baseURL.appendingPathComponent(ref.replacingOccurrences(of: " ", with: "_"))
    }
}

private struct VersionCandidate {
    let language: String?
    let languageFamily: String?
    let text: String
    let isSource: Bool
    let isPrimary: Bool
    let priority: Double
    let versionTitle: String?
    let direction: String?

    var preferenceScore: Int {
        (isSource ? 2 : 0) + (isPrimary ? 1 : 0)
    }
}

private enum NativeAppSefariaError: LocalizedError {
    case invalidReference
    case unresolvedReference(String)
    case invalidResponse
    case noText(String)

    var errorDescription: String? {
        switch self {
        case .invalidReference:
            return String(localized: "The Sefaria reference is empty.")
        case .unresolvedReference(let reference):
            return String(localized: "Sefaria could not resolve the reference: \(reference)")
        case .invalidResponse:
            return String(localized: "Sefaria returned an invalid response.")
        case .noText(let reference):
            return String(localized: "Sefaria returned no readable text for: \(reference)")
        }
    }
}
