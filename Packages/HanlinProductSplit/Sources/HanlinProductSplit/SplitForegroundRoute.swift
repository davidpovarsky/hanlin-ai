import Foundation

/// A product wake hint, never a caller identity, request body, or authorization.
/// Custom scheme registration/open success does not authenticate the receiving app.
public enum SplitForegroundRoute: String, Codable, CaseIterable, Sendable {
    case openMiniApps, returnToAI

    private var scheme: String { self == .openMiniApps ? "hanlinminiapps" : "chavrusachat" }
    private var action: String { self == .openMiniApps ? "open" : "return" }

    public func url(reference: UUID) -> URL {
        URL(string: "\(scheme)://split/v1/\(action)/\(reference.uuidString.lowercased())")!
    }

    public func reference(in url: URL) throws -> UUID {
        guard url.absoluteString.utf8.count <= 128,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == scheme, parts.host == "split",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { throw SplitBridgeFailure.malformed }
        let prefix = "/v1/\(action)/"
        guard parts.percentEncodedPath.hasPrefix(prefix),
              let id = UUID(uuidString: String(parts.percentEncodedPath.dropFirst(prefix.count))),
              self.url(reference: id).absoluteString == url.absoluteString else { throw SplitBridgeFailure.malformed }
        return id
    }
}
