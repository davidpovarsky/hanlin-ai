//
//  YouKeylessSearchAdapter.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Adapter for You.com Keyless Search API.
/// Endpoint: GET https://api.you.com/v1/agents/search?query=...&count=...
public struct YouKeylessSearchAdapter: WebSearchProvider {
    public let providerID: String = "you"
    public let displayName: String = "You.com Keyless"
    
    private let session: URLSession
    private let baseURL: URL
    
    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.you.com/v1/agents/search")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }
    
    public func search(query: String, count: Int, timeout: TimeInterval) async throws -> [WebSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AutomaticSearchError.invalidQuery
        }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "count", value: String(max(1, min(count, 10))))
        ]
        
        guard let requestURL = components?.url else {
            throw AutomaticSearchError.networkError("Invalid URL construction for You.com search")
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HanlinAI/1.0", forHTTPHeaderField: "User-Agent")
        
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
            let retrySeconds = HTTPHeaderParser.parseRetryAfter(from: httpResponse)
            throw AutomaticSearchError.rateLimited(retryAfter: retrySeconds)
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AutomaticSearchError.providerUnavailable("\(displayName) authorization/policy rejected (HTTP \(httpResponse.statusCode))")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data.prefix(500), encoding: .utf8) ?? "Unknown server error"
            throw AutomaticSearchError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        let decoded = try parseYouResponse(data: data)
        guard !decoded.isEmpty else {
            throw AutomaticSearchError.emptyResults
        }
        return decoded
    }
    
    // MARK: - Response Parsing
    
    public func parseYouResponse(data: Data) throws -> [WebSearchResult] {
        struct YouResponse: Codable {
            struct ResultsContainer: Codable {
                let web: [YouWebItem]?
            }
            let results: ResultsContainer?
        }
        
        struct YouWebItem: Codable {
            let url: String?
            let title: String?
            let description: String?
            let thumbnail_url: String?
            let favicon_url: String?
            
            enum CodingKeys: String, CodingKey {
                case url, title, description, thumbnail_url, favicon_url, snippets
            }
            
            let snippetsText: String?
            
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.url = try container.decodeIfPresent(String.self, forKey: .url)
                self.title = try container.decodeIfPresent(String.self, forKey: .title)
                self.description = try container.decodeIfPresent(String.self, forKey: .description)
                self.thumbnail_url = try container.decodeIfPresent(String.self, forKey: .thumbnail_url)
                self.favicon_url = try container.decodeIfPresent(String.self, forKey: .favicon_url)
                
                if let singleString = try? container.decode(String.self, forKey: .snippets) {
                    self.snippetsText = singleString
                } else if let stringArray = try? container.decode([String].self, forKey: .snippets) {
                    self.snippetsText = stringArray.joined(separator: " ")
                } else {
                    self.snippetsText = nil
                }
            }
        }
        
        do {
            let parsed = try JSONDecoder().decode(YouResponse.self, data: data)
            let items = parsed.results?.web ?? []
            return items.compactMap { item in
                guard let url = item.url, !url.isEmpty,
                      let title = item.title, !title.isEmpty else {
                    return nil
                }
                let snippet = (item.snippetsText?.isEmpty == false ? item.snippetsText : item.description) ?? ""
                let icon = item.favicon_url ?? item.thumbnail_url ?? ""
                return WebSearchResult(
                    title: title,
                    url: url,
                    snippet: snippet,
                    icon: icon,
                    sourceBackend: "you"
                )
            }
        } catch {
            throw AutomaticSearchError.decodingError(error.localizedDescription)
        }
    }
}
