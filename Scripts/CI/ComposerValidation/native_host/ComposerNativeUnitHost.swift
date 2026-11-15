import SwiftUI

// Infrastructure only. The production component files remain separate, unchanged.
@main
struct ComposerNativeUnitHost: App {
    var body: some Scene {
        WindowGroup {
            Color.clear
                .accessibilityHidden(true)
        }
    }
}
