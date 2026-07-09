import Foundation

struct SefariaClient {
    var baseURL = URL(string: "https://www.sefaria.org")!

    func search(query: String, limit: Int) async throws -> [NativeAppSefariaSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/search-wrapper"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "type", value: "text"),
            URLQueryItem(name: "size", value: String(max(1, min(limit, 10))))
        ]
        guard let url = components.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rawHits = (json["hits"] as? [[String: Any]])
            ?? (json["results"] as? [[String: Any]])
            ?? ((json["hits"] as? [String: Any])?["hits"] as? [[String: Any]])
            ?? []

        return rawHits.prefix(limit).compactMap { hit in
            let source = hit["_source"] as? [String: Any] ?? hit
            let ref = source["ref"] as? String
                ?? source["title"] as? String
                ?? hit["ref"] as? String
                ?? hit["title"] as? String
            guard let ref, !ref.isEmpty else { return nil }

            let snippet = (source["content"] as? String)
                ?? (source["exact"] as? String)
                ?? (hit["snippet"] as? String)
                ?? ""

            return NativeAppSefariaSearchResult(
                ref: ref,
                title: source["title"] as? String ?? ref,
                snippet: snippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                url: URL(string: "https://www.sefaria.org/" + ref.replacingOccurrences(of: " ", with: "_"))
            )
        }
    }

    func source(ref: String) async throws -> NativeAppSefariaSource {
        let encodedRef = ref.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        var components = URLComponents(url: baseURL.appendingPathComponent("api/texts/\(encodedRef)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "context", value: "0")]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let text = Self.flattenText(json["text"]) ?? ""
        let heText = Self.flattenText(json["he"])
        let normalizedRef = json["ref"] as? String ?? ref
        return NativeAppSefariaSource(
            ref: normalizedRef,
            text: text,
            heText: heText,
            url: URL(string: "https://www.sefaria.org/" + normalizedRef.replacingOccurrences(of: " ", with: "_"))
        )
    }

    private static func flattenText(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [String] { return array.joined(separator: "\n") }
        if let nested = value as? [[String]] { return nested.map { $0.joined(separator: " ") }.joined(separator: "\n") }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { flattenText($0) }.joined(separator: "\n")
        }
        return nil
    }
}
