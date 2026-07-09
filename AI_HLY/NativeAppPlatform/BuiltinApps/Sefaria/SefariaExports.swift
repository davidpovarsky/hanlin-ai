import SwiftUI

@MainActor
enum SefariaExports {
    static func client() -> SefariaClient {
        SefariaClient()
    }

    static func searchService() -> SefariaSearchService {
        SefariaSearchService(client: client())
    }

    static func sourceService() -> SefariaSourceService {
        SefariaSourceService(client: client())
    }

    static func rootView(context: NativeAppContext) -> AnyView {
        AnyView(
            SefariaRootView(
                searchService: searchService(),
                sourceService: sourceService(),
                context: context
            )
        )
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            NativeAppSefariaSearchTool(service: searchService()),
            NativeAppSefariaSourceTool(service: sourceService())
        ]
    }

    static func sourceCard(source: SefariaSource, mode: NativePresentationMode) -> AnyView {
        AnyView(SefariaSourceCard(source: source, mode: mode))
    }
}
