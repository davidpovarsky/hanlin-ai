//
//  WebSearchResult.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Canonical typed representation of an individual web search result across all providers.
public struct WebSearchResult: Sendable, Equatable, Hashable, Codable {
    public let title: String
    public let url: String
    public let snippet: String
    public let icon: String
    public let sourceBackend: String
    public let score: Double?
    public let publishedDate: String?
    
    public init(
        title: String,
        url: String,
        snippet: String,
        icon: String = "",
        sourceBackend: String = "unknown",
        score: Double? = nil,
        publishedDate: String? = nil
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        self.icon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceBackend = sourceBackend
        self.score = score
        self.publishedDate = publishedDate
    }
    
    /// Normalizes URL for canonical deduplication (strips query tracking, anchors, and trailing slashes).
    public var canonicalURLString: String {
        guard let components = URLComponents(string: url) else {
            return url.lowercased()
        }
        var cleanComponents = URLComponents()
        cleanComponents.scheme = components.scheme?.lowercased()
        cleanComponents.host = components.host?.lowercased()
        cleanComponents.port = components.port
        cleanComponents.path = components.path.hasSuffix("/") && components.path.count > 1
            ? String(components.path.dropLast())
            : components.path
        
        // Retain non-tracking query items
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") &&
                       name != "fbclid" &&
                       name != "gclid" &&
                       name != "msclkid" &&
                       name != "ref"
            }
            if !filtered.isEmpty {
                cleanComponents.queryItems = filtered
            }
        }
        return cleanComponents.url?.absoluteString ?? url.lowercased()
    }
    
    /// Checks basic structural validity of the search result.
    public var isValid: Bool {
        guard !title.isEmpty, !snippet.isEmpty, !url.isEmpty else { return false }
        guard let parsedURL = URL(string: url),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsedURL.host,
              !host.isEmpty else {
            return false
        }
        return true
    }
    
    /// Converts a collection of typed WebSearchResults into legacy ParsedSearchResult
    /// ensuring all parallel arrays (titles, links, contents, icons) remain strictly synchronized.
    public static func toParsedSearchResult(_ results: [WebSearchResult], defaultIcon: String = "") -> ParsedSearchResult {
        var titles: [String] = []
        var links: [String] = []
        var contents: [String] = []
        var icons: [String] = []
        
        for item in results where item.isValid {
            titles.append(item.title)
            links.append(item.url)
            contents.append(item.snippet)
            let iconURL = item.icon.isEmpty ? defaultIcon : item.icon
            icons.append(iconURL)
        }
        
        return ParsedSearchResult(
            titles: titles,
            links: links,
            contents: contents,
            icons: icons,
            totalTokens: contents.reduce(0) { $0 + $1.count }
        )
    }
}
