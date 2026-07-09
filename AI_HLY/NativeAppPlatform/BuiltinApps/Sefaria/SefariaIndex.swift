import Foundation

@MainActor
enum SefariaIndex {
    static let id = "nativeapp.sefaria"

    static func module() -> NativeAppModule {
        SefariaAppModule()
    }
}
