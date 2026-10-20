//
//  KeenablePublicSearchAdapter.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Adapter for Keenable Public Search API.
/// Endpoint: POST https://api.keenable.ai/v1/search/public
public struct KeenablePublicSearchAdapter: WebSearchProvider {
    public let providerID: String = "keenable"
    public let displayName: String = "Keenable Public"
    
    private let session: URLSession
    private let endpointURL: URL
    
    public init(
        session: URLSession = .shared,
        endpointURL: URL = URL(string: "https://api.keenable.ai/v1/search/public")!
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
        request.setValue("HanlinAI-App", forHTTPHeaderField: "X-Keenable-Title")
        request.setValue("HanlinAI/1.0", forHTTPHeaderField: "User-Agent")
        
        let bodyPayload: [String: Any] = [
            "query": query,
            "max_results": max(1, min(count, 10))
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload, options: [])
        } catch {
            throw AutomaticSearchError.networkError("Failed to serialize Keenable search payload")
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
        
        let decoded = try parseKeenableResponse(data: data)
        guard !decoded.isEmpty else {
            throw AutomaticSearchError.emptyResults
        }
        return decoded
    }
    
    // MARK: - Response Parsing
    
    private func parseKeenableResponse(data: Data) throws -> [WebSearchResult] {
        struct KeenableResponse: Codable {
            struct KeenableItem: Codable {
                let url: String?
                let title: String?
                let snippet: String?
                let description: String?
                let acquired_at: String?
            }
            let results: [KeenableItem]?
        }
        
        do {
            let parsed = try JSONDecoder().decode(KeenableResponse.self, data: data)
            let items = parsed.results ?? []
            return items.compactMap { item in
                guard let url = item.url, !url.isEmpty,
                      let title = item.title, !title.isEmpty else {
                    return nil
                }
                let snippet = (item.snippet?.isEmpty == false ? item.snippet : item.description) ?? ""
                return WebSearchResult(
                    title: title,
                    url: url,
                    snippet: snippet,
                    sourceBackend: "keenable",
                    publishedDate: item.acquired_at
                )
            }
        } catch {
            throw AutomaticSearchError.decodingError(error.localizedDescription)
        }
    }
}
