import Foundation

public enum TorahDeepLinkAction: String, Codable, Sendable {
    case open = "open"
    case learn = "learn"
    case lookup = "lookup"
}

public struct TorahStudyDeepLink: Codable, Hashable, Sendable {
    public let action: TorahDeepLinkAction
    public let locator: SourceLocator
    public let generation: String
    public let workTitle: String?
    public let highlightText: String?
    public let requestID: String?

    public init(
        action: TorahDeepLinkAction = .open,
        locator: SourceLocator,
        generation: String = "default",
        workTitle: String? = nil,
        highlightText: String? = nil,
        requestID: String? = nil
    ) {
        self.action = action
        self.locator = locator
        self.generation = generation
        self.workTitle = workTitle
        self.highlightText = highlightText
        self.requestID = requestID
    }

    /// Serializes this deep link into a URL with the given scheme (`maktabah`, `itorah`, or `hanlin`).
    public func url(scheme: String = "maktabah") -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "study"

        var items: [URLQueryItem] = [
            URLQueryItem(name: "action", value: action.rawValue),
            URLQueryItem(name: "provider", value: locator.providerID),
            URLQueryItem(name: "corpus", value: locator.corpusID),
            URLQueryItem(name: "generation", value: generation),
            URLQueryItem(name: "work", value: locator.workKey),
            URLQueryItem(name: "pos_kind", value: locator.positionKind.rawValue),
            URLQueryItem(name: "pos_val", value: locator.positionValue)
        ]

        if let title = workTitle {
            items.append(URLQueryItem(name: "title", value: title))
        }
        if let highlight = highlightText {
            items.append(URLQueryItem(name: "highlight", value: highlight))
        }
        if let reqID = requestID {
            items.append(URLQueryItem(name: "req_id", value: reqID))
        }

        components.queryItems = items
        return components.url
    }

    /// Parses a URL into a `TorahStudyDeepLink` if valid.
    public static func parse(url: URL) -> TorahStudyDeepLink? {
        guard let scheme = url.scheme?.lowercased(),
              ["maktabah", "itorah", "hanlin"].contains(scheme),
              url.host?.lowercased() == "study",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        func value(for name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let actionStr = value(for: "action"),
              let action = TorahDeepLinkAction(rawValue: actionStr),
              let provider = value(for: "provider"),
              let corpus = value(for: "corpus"),
              let work = value(for: "work"),
              let posKindStr = value(for: "pos_kind"),
              let posKind = PositionKind(rawValue: posKindStr),
              let posVal = value(for: "pos_val") else {
            return nil
        }

        let generation = value(for: "generation") ?? "default"
        let locator = SourceLocator(
            providerID: provider,
            corpusID: corpus,
            corpusGeneration: generation,
            workKey: work,
            positionKind: posKind,
            positionValue: posVal
        )

        return TorahStudyDeepLink(
            action: action,
            locator: locator,
            generation: generation,
            workTitle: value(for: "title"),
            highlightText: value(for: "highlight"),
            requestID: value(for: "req_id")
        )
    }
}
