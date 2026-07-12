import Foundation

struct NativeAppRoute: Identifiable, Codable, Hashable {
    var id: String {
        [appID, screen, stablePayloadID].filter { !$0.isEmpty }.joined(separator: ":")
    }

    let appID: String
    let screen: String
    let payload: NativeAppRoutePayload

    init(appID: String, screen: String, payload: NativeAppRoutePayload = .empty) {
        self.appID = appID
        self.screen = screen
        self.payload = payload
    }

    private var stablePayloadID: String {
        switch payload {
        case .empty:
            return ""
        case .dictionary(let values):
            return values.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
        }
    }
}

enum NativeAppRoutePayload: Codable, Hashable {
    case empty
    case dictionary([String: String])

    var values: [String: String] {
        switch self {
        case .empty: return [:]
        case .dictionary(let values): return values
        }
    }

    func string(_ key: String) -> String? { values[key] }
}

extension NativeAppRoute {
    static func textStudioEditor(text: String) -> NativeAppRoute {
        NativeAppRoute(appID: NativeAppTextStudioIndex.id, screen: "editor", payload: .dictionary(["text": text]))
    }

    static func textStudioTransform(text: String, transform: String) -> NativeAppRoute {
        NativeAppRoute(
            appID: NativeAppTextStudioIndex.id,
            screen: "transform",
            payload: .dictionary(["text": text, "transform": transform])
        )
    }

    static func sefariaSearch(query: String) -> NativeAppRoute {
        NativeAppRoute(appID: NativeAppSefariaIndex.id, screen: "search", payload: .dictionary(["query": query]))
    }

    static func sefariaSource(ref: String) -> NativeAppRoute {
        NativeAppRoute(appID: NativeAppSefariaIndex.id, screen: "source", payload: .dictionary(["ref": ref]))
    }

    static func wikipediaSearch(query: String, languageCode: String? = nil) -> NativeAppRoute {
        var values = ["query": query]
        if let languageCode, !languageCode.isEmpty { values["languageCode"] = languageCode }
        return NativeAppRoute(appID: NativeAppWikipediaIndex.id, screen: "search", payload: .dictionary(values))
    }

    static func wikipediaArticle(title: String, languageCode: String) -> NativeAppRoute {
        NativeAppRoute(
            appID: NativeAppWikipediaIndex.id,
            screen: "article",
            payload: .dictionary(["title": title, "languageCode": languageCode])
        )
    }
}
