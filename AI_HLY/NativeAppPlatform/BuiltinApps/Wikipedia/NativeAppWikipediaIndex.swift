import Foundation

@MainActor
enum NativeAppWikipediaIndex {
    nonisolated static let id = "nativeapp.wikipedia"

    static func module() -> NativeAppModule {
        NativeAppWikipediaAppModule()
    }
}
