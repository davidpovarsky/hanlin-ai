import Foundation

@MainActor
enum NativeAppWikipediaIndex {
    static let id = "nativeapp.wikipedia"

    static func module() -> NativeAppModule {
        NativeAppWikipediaAppModule()
    }
}
