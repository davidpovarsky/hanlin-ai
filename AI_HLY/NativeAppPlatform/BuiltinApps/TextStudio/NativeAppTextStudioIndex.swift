import Foundation

@MainActor
enum NativeAppTextStudioIndex {
    nonisolated static let id = "nativeapp.textstudio"

    static func module() -> NativeAppModule {
        NativeAppTextStudioAppModule()
    }
}
