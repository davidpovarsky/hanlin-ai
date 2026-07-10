import Foundation

@MainActor
enum NativeAppSefariaIndex {
    static let id = "nativeapp.sefaria"

    static func module() -> NativeAppModule {
        NativeAppSefariaAppModule()
    }
}
