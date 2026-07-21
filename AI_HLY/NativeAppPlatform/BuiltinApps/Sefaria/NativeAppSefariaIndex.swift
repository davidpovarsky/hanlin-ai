import Foundation

@MainActor
enum NativeAppSefariaIndex {
    nonisolated static let id = "nativeapp.sefaria"

    static func module() -> NativeAppModule {
        NativeAppSefariaAppModule()
    }
}
