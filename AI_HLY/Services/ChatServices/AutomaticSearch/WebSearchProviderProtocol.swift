//
//  WebSearchProviderProtocol.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation

/// Protocol for isolated web search backend adapters.
public protocol WebSearchProvider: Sendable {
    /// Unique stable identifier for the provider (e.g. "you", "tavily", "keenable").
    var providerID: String { get }
    
    /// User-facing display name for the backend.
    var displayName: String { get }
    
    /// Executes a search query with requested count and bounded timeout.
    func search(query: String, count: Int, timeout: TimeInterval) async throws -> [WebSearchResult]
}

/// Errors thrown by search providers and coordinator.
public enum AutomaticSearchError: LocalizedError, Sendable, Equatable {
    case invalidQuery
    case networkError(String)
    case httpError(statusCode: Int, message: String)
    case rateLimited(retryAfter: TimeInterval?)
    case decodingError(String)
    case emptyResults
    case providerUnavailable(String)
    case allProvidersFailed(reasons: [String])
    case cancelled
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "The search query is empty or invalid."
        case .networkError(let message):
            return "Network connection error: \(message)"
        case .httpError(let statusCode, let message):
            return "Search provider returned HTTP \(statusCode): \(message)"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Search rate limit exceeded. Retry after \(Int(retry))s."
            }
            return "Search rate limit exceeded. Please wait a moment."
        case .decodingError(let message):
            return "Failed to decode search response: \(message)"
        case .emptyResults:
            return "No relevant search results were returned."
        case .providerUnavailable(let provider):
            return "Provider '\(provider)' is temporarily unavailable or on cooldown."
        case .allProvidersFailed(let reasons):
            return "All keyless search backends failed. Details: " + reasons.joined(separator: "; ")
        case .cancelled:
            return "The search task was cancelled."
        case .timeout:
            return "Search request timed out."
        }
    }
}
