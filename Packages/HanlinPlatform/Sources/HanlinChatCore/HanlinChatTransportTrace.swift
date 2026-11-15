import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Observations of bytes delivered to the parser/SDK, not TLS packets. The
/// observer must enqueue work and return promptly; it never consumes the body.
public enum HanlinChatTransportEvent: Sendable {
    case request(id: UUID, request: URLRequest)
    case response(id: UUID, response: HTTPURLResponse)
    case bytes(id: UUID, data: Data)
    case end(id: UUID, error: String?)
}

public typealias HanlinChatTransportObserver = @Sendable (HanlinChatTransportEvent) -> Void
