import AppIntents
import HanlinScriptExtensions

/// Register this package from every app/extension that hosts these original
/// entity queries and intents, including foreground script handoffs.
public struct HanlinWidgetIntentsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinScriptExtensionIntentsPackage.self]
    }
}
