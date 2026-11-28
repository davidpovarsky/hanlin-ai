import Foundation

@MainActor
enum BuiltinAppsIndex {
    static func modules() -> [NativeAppModule] {
        [
            NativeAppSefariaIndex.module(),
            NativeAppWikipediaIndex.module(),
            NativeAppTextStudioIndex.module()
        ]
    }
}
