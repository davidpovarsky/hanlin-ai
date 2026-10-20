//
//  TavilyKeylessSearchAdapter.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Adapter for Tavily Keyless Search API.
/// Endpoint: POST https://api.tavily.com/search
public struct TavilyKeylessSearchAdapter: WebSearchProvider {
    public let providerID: String = "tavily"
    public let displayName: String = "Tavily Keyless"
    
    private let session: URLSession
    private let endpointURL: URL
    private static let defaultIconURL = "https://yyz2.discourse-cdn.com/flex004/user_avatar/community.tavily.com/system/288/107_2.png"
    
    public init(
        session: URLSession = .shared,
        endpointURL: URL = URL(string: "https://api.tavily.com/search")!
    ) {
        self.session = session
        self.endpointURL = endpointURL
    }
    
    public func search(query: String, count: Int, timeout: TimeInterval) async throws -> [WebSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AutomaticSearchError.invalidQuery
        }
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("keyless", forHTTPHeaderField: "x-tavily-access-mode")
        request.setValue("HanlinAI/1.0", forHTTPHeaderField: "User-Agent")
        
        let bodyPayload: [String: Any] = [
            "query": query,
            "max_results": max(1, min(count, 10))
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload, options: [])
        } catch {
            throw AutomaticSearchError.networkError("Failed to serialize Tavily search payload")
        }
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw AutomaticSearchError.cancelled
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AutomaticSearchError.timeout
        } catch {
            throw AutomaticSearchError.networkError(error.localizedDescription)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AutomaticSearchError.networkError("Non-HTTP response received")
        }
        
        if httpResponse.statusCode == 429 {
            var retrySeconds: TimeInterval? = nil
            if let retryHeader = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let seconds = Double(retryHeader) {
                retrySeconds = seconds
            }
            throw AutomaticSearchError.rateLimited(retryAfter: retrySeconds)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data.prefix(500), encoding: .utf8) ?? "Unknown server error"
            throw AutomaticSearchError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        let decoded = try parseTavilyResponse(data: data)
        guard !decoded.isEmpty else {
            throw AutomaticSearchError.emptyResults
        }
        return decoded
    }
    
    // MARK: - Response Parsing
    
    private func parseTavilyResponse(data: Data) throws -> [WebSearchResult] {
        struct TavilyResponse: Codable {
            struct TavilyItem: Codable {
                let url: String?
                let title: String?
                let content: String?
                let score: Double?
            }
            let results: [TavilyItem]?
        }
        
        do {
            let parsed = try JSONDecoder().decode(TavilyResponse.self, data: data)
            let items = parsed.results ?? []
            return items.compactMap { item in
                guard let url = item.url, !url.isEmpty,
                      let title = item.title, !title.isEmpty else {
                    return nil
                }
                return WebSearchResult(
                    title: title,
                    url: url,
                    snippet: item.content ?? "",
                    icon: Self.defaultIconURL,
                    sourceBackend: "tavily",
                    score: item.score
                )
            }
        } catch {
            throw AutomaticSearchError.decodingError(error.localizedDescription)
        }
    }
}
