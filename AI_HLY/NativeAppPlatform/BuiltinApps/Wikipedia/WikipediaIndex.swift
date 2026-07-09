import Foundation

@MainActor
enum WikipediaIndex {
    static let id = "nativeapp.wikipedia"

    static func module() -> NativeAppModule {
        WikipediaAppModule()
    }
}
