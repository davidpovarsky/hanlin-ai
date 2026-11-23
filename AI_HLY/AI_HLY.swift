import AI_Hanlin
import SwiftUI

#if HANLIN_NATIVESCRIPT_POC
@main
struct HanlinNativeScriptPOCApp: App {
    var body: some Scene {
        WindowGroup { HanlinNativeScriptAcceptanceView() }
    }
}
#else
@main
@MainActor
struct MyApp: App {
    private let context: HanlinApplicationContext

    init() {
        do { context = try HanlinApplicationContext(configuration: .hanlin) }
        catch { fatalError("Unable to initialize Hanlin: \(error)") }
    }

    var body: some Scene {
        HanlinApplicationScene(context: context)
    }
}
#endif
