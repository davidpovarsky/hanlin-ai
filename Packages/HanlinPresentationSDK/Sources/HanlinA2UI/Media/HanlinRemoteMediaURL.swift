import Foundation

/// Lexical admission before constructing an upstream media view. This does not claim
/// DNS/redirect validation, response bounds or decoded-image limits.
public struct HanlinRemoteMediaURL: Hashable, Sendable {
    public let url: URL

    public init?(_ value: String) {
        guard value.utf8.count <= 4096,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              components.percentEncodedHost?.contains("%") == false,
              !host.contains(":"), !host.hasSuffix(".") else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }), let last = labels.last, last.utf8.contains(where: { (97...122).contains($0) }),
              !["localhost", "local", "internal", "invalid", "test", "example", "onion"].contains(String(last)),
              host != "home.arpa", !host.hasSuffix(".home.arpa"),
              let url = components.url else { return nil }
        self.url = url
    }
}
