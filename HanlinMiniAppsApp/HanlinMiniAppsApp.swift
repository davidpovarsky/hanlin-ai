import SwiftUI

/// New target entry point. Membership, entitlements and concrete composition are
/// deliberately reserved for the integration lease; this is not an installed app.
@main
struct HanlinMiniAppsApplication: App {
    var body: some Scene {
        WindowGroup { MiniAppsLibrary(services: .unconfigured) }
    }
}
