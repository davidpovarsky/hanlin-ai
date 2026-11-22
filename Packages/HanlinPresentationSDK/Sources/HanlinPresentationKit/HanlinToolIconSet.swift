import Foundation

/// Provider-declared artwork is presentation only. It carries no tool identity,
/// permission, source evidence or executable content.
public struct HanlinToolIcon: Codable, Hashable, Sendable {
    public enum Theme: String, Codable, Hashable, Sendable {
        case light, dark
    }

    public let url: URL
    public let theme: Theme?

    public init?(source: String, theme: Theme? = nil) {
        guard let url = Self.safeURL(source) else { return nil }
        self.url = url
        self.theme = theme
    }

    private enum CodingKeys: String, CodingKey { case url, theme }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let source = try values.decode(String.self, forKey: .url)
        let rawTheme = try values.decodeIfPresent(String.self, forKey: .theme)
        let theme = rawTheme.flatMap(Theme.init(rawValue:))
        guard rawTheme == nil || theme != nil,
              let icon = Self(source: source, theme: theme) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: values,
                debugDescription: "Unusable tool icon metadata")
        }
        self = icon
    }

    public static func safeURL(_ source: String) -> URL? {
        guard source.utf8.count <= 8_192,
              !source.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              var components = URLComponents(string: source),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        components.scheme = "https"
        guard let url = components.url, url.absoluteString.utf8.count <= 8_192 else { return nil }
        return url
    }
}

/// Keep the tool and server tiers separate so theme matching and failed image
/// loads can fall back without borrowing another tool's or server's artwork.
public struct HanlinToolIconSet: Codable, Hashable, Sendable {
    public let tool: [HanlinToolIcon]
    public let server: [HanlinToolIcon]

    public init?(tool: [HanlinToolIcon], server: [HanlinToolIcon]) {
        self.tool = Self.bounded(tool)
        self.server = Self.bounded(server)
        guard !self.tool.isEmpty || !self.server.isEmpty else { return nil }
    }

    private enum CodingKeys: String, CodingKey { case tool, server }

    public init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else {
            tool = []; server = []; return
        }
        func admitted(_ key: CodingKeys) -> [HanlinToolIcon] {
            guard var items = try? values.nestedUnkeyedContainer(forKey: key) else { return [] }
            var icons: [HanlinToolIcon] = []
            for _ in 0..<8 where !items.isAtEnd {
                // A bad URL, future theme or malformed decorative entry must
                // not make the surrounding historical conversation unreadable.
                guard let item = try? items.superDecoder() else { break }
                if let icon = try? HanlinToolIcon(from: item) { icons.append(icon) }
            }
            return Self.bounded(icons)
        }
        tool = admitted(.tool)
        server = admitted(.server)
    }

    public func candidateURLs(for theme: HanlinToolIcon.Theme) -> [URL] {
        var urls: [URL] = []
        var seen = Set<URL>()
        for tier in [Self.bounded(tool), Self.bounded(server)] {
            // A declared opposite-theme icon may be invisible on this surface.
            // Prefer the current theme, then an explicitly theme-neutral icon.
            let themes: [HanlinToolIcon.Theme?] = [theme, nil]
            var tierCount = 0
            for requestedTheme in themes {
                for icon in tier where icon.theme == requestedTheme {
                    guard tierCount < 2,
                          let url = HanlinToolIcon.safeURL(icon.url.absoluteString),
                          seen.insert(url).inserted else { continue }
                    urls.append(url)
                    tierCount += 1
                }
            }
        }
        return urls
    }

    private static func bounded(_ icons: [HanlinToolIcon]) -> [HanlinToolIcon] {
        var seen = Set<HanlinToolIcon>()
        // Admission and replay use the same bound. Revalidate decoded metadata;
        // Codable must not turn an old or malformed URL into a fetch target.
        return icons.prefix(8).compactMap { icon in
            guard let safe = HanlinToolIcon(source: icon.url.absoluteString, theme: icon.theme),
                  seen.insert(safe).inserted else { return nil }
            return safe
        }
    }
}
