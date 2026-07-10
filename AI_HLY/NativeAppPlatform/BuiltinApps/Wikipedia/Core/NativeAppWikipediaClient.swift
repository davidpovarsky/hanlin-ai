import Foundation

struct NativeAppWikipediaClient {
    func search(query: String, limit: Int, languageCode: String) async throws -> [NativeAppWikipediaSearchResult] {
        var components = URLComponents(string: "https://\(languageCode).wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 20)))),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.validate(response)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any], array.count >= 4 else { return [] }
        let titles = array[1] as? [String] ?? []
        let descriptions = array[2] as? [String] ?? []
        let urls = array[3] as? [String] ?? []
        return titles.enumerated().map { index, title in
            NativeAppWikipediaSearchResult(
                title: title,
                description: descriptions.indices.contains(index) ? descriptions[index] : "",
                url: urls.indices.contains(index) ? URL(string: urls[index]) : nil,
                languageCode: languageCode
            )
        }
    }

    func summary(title: String, languageCode: String) async throws -> NativeAppWikipediaSummary {
        let encodedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let url = URL(string: "https://\(languageCode).wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.validate(response)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let contentURLs = json["content_urls"] as? [String: Any]
        let desktop = contentURLs?["desktop"] as? [String: Any]
        let thumbnail = json["thumbnail"] as? [String: Any]
        return NativeAppWikipediaSummary(
            title: json["title"] as? String ?? title,
            extract: json["extract"] as? String ?? "",
            description: json["description"] as? String,
            url: URL(string: desktop?["page"] as? String ?? ""),
            thumbnailURL: URL(string: thumbnail?["source"] as? String ?? ""),
            languageCode: languageCode
        )
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
