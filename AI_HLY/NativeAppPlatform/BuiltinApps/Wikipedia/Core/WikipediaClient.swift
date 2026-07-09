import Foundation

struct WikipediaClient {
    var languageCode = "en"

    private var apiBaseURL: URL { URL(string: "https://\(languageCode).wikipedia.org")! }

    func search(query: String, limit: Int) async throws -> [WikipediaSearchResult] {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("w/api.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "opensearch"),
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 10)))),
            URLQueryItem(name: "namespace", value: "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [Any], array.count >= 4 else { return [] }
        let titles = array[1] as? [String] ?? []
        let descriptions = array[2] as? [String] ?? []
        let urls = array[3] as? [String] ?? []
        return titles.enumerated().map { index, title in
            WikipediaSearchResult(
                title: title,
                description: descriptions.indices.contains(index) ? descriptions[index] : "",
                url: urls.indices.contains(index) ? URL(string: urls[index]) : nil
            )
        }
    }

    func summary(title: String) async throws -> WikipediaSummary {
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let url = apiBaseURL.appendingPathComponent("api/rest_v1/page/summary/\(encodedTitle)")
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let contentURLs = json["content_urls"] as? [String: Any]
        let desktop = contentURLs?["desktop"] as? [String: Any]
        let thumbnail = json["thumbnail"] as? [String: Any]
        return WikipediaSummary(
            title: json["title"] as? String ?? title,
            extract: json["extract"] as? String ?? "",
            description: json["description"] as? String,
            url: URL(string: desktop?["page"] as? String ?? ""),
            thumbnailURL: URL(string: thumbnail?["source"] as? String ?? "")
        )
    }
}
