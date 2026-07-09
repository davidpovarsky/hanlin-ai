import Foundation

@MainActor
enum TextToolkitIndex {
    static let id = "nativeapp.text_toolkit"

    static func module() -> NativeAppModule {
        TextToolkitAppModule()
    }
}
