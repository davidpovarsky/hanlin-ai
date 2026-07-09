import Foundation

@MainActor
enum BuiltinAppsIndex {
    static func modules() -> [NativeAppModule] {
        [
            SefariaIndex.module(),
            WikipediaIndex.module(),
            TextToolkitIndex.module()
        ]
    }
}
