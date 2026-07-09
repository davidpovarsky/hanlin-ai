import SwiftUI

@MainActor
enum SefariaExports {
    static func client() -> SefariaClient {
        SefariaClient()
    }

    static func searchService() -> SefariaSearchService {
        SefariaSearchService(client: client())
    }

    static func sourceService() -> NativeAppSefariaSourceService {
        NativeAppSefariaSourceService(client: client())
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

    static func sourceCard(source: NativeAppSefariaSource, mode: NativePresentationMode) -> AnyView {
        AnyView(NativeAppSefariaSourceCard(source: source, mode: mode))
    }
}
