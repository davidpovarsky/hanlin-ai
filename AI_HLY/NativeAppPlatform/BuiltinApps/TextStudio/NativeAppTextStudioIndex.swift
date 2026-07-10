import Foundation

@MainActor
enum NativeAppTextStudioIndex {
    static let id = "nativeapp.textstudio"

    static func module() -> NativeAppModule {
        NativeAppTextStudioAppModule()
    }
}
