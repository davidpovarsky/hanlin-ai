// Original shared implementation is owned by the SDK.
import HanlinAgentActivityCore

typealias NativeAppRoute = HanlinAgentActivityCore.NativeAppRoute
typealias NativeAppRoutePayload = HanlinAgentActivityCore.NativeAppRoutePayload
import Foundation

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
