import Foundation

/// A normalized YouTube identity, not a direct MP4/HLS URL or arbitrary HTML.
public struct HanlinYouTubeVideo: Hashable, Sendable {
    public let id: String

    public init?(id: String) {
        guard id.utf8.count == 11, id.utf8.allSatisfy({ byte in
            (65...90).contains(byte) || (97...122).contains(byte)
                || (48...57).contains(byte) || byte == 45 || byte == 95
        }) else { return nil }
        self.id = id
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.user == nil,
              components.password == nil, components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), !components.percentEncodedPath.contains("%") else { return nil }
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
        let videoID: String
        switch host {
        case "youtu.be", "www.youtu.be":
            guard segments.count == 2, segments[0].isEmpty else { return nil }
            videoID = String(segments[1])
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            if components.path == "/watch" {
                let ids = (components.queryItems ?? []).filter { $0.name == "v" }
                guard ids.count == 1, let value = ids[0].value else { return nil }
                videoID = value
            } else {
                guard segments.count == 3, segments[0].isEmpty,
                      ["shorts", "embed"].contains(segments[1]) else { return nil }
                videoID = String(segments[2])
            }
        case "youtube-nocookie.com", "www.youtube-nocookie.com":
            guard segments.count == 3, segments[0].isEmpty, segments[1] == "embed" else { return nil }
            videoID = String(segments[2])
        default: return nil
        }
        self.init(id: videoID)
    }

    public var sourceURL: URL {
        // The validated eleven ASCII characters cannot introduce another path/query/authority.
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}
