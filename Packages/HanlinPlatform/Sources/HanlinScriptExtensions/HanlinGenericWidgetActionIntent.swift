import AppIntents
import Foundation
import HanlinPlatformContracts
import WidgetKit

@available(iOS 17.0, *)
public struct HanlinGenericWidgetActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Hanlin Widget Action"
    public static let isDiscoverable: Bool = false

    @Parameter(title: "packageID")
    public var packageID: String

    @Parameter(title: "entrypointID")
    public var entrypointID: String

    @Parameter(title: "target")
    public var target: String

    @Parameter(title: "environment")
    public var environment: String

    public init() {
        self.packageID = ""
        self.entrypointID = ""
        self.target = ""
        self.environment = "{}"
    }

    public init(packageID: String, entrypointID: String, target: String, environment: String = "{}") {
        self.packageID = packageID
        self.entrypointID = entrypointID
        self.target = target
        self.environment = environment
    }

    public func perform() async throws -> some IntentResult {
        if let store = try? HanlinScriptExtensionStore() {
            let pkg = packageID.isEmpty ? "hanlin-widget" : packageID
            let entry = entrypointID.isEmpty ? "default" : entrypointID
            let invocation = HanlinScriptIntentInvocation(
                identity: HanlinScriptExtensionIdentity(
                    installedPackageID: HanlinInstalledPackageID(unchecked: pkg),
                    packageID: HanlinPackageID(unchecked: pkg),
                    generation: 1,
                    entrypointID: entry
                ),
                entityID: target,
                parameters: .string(environment),
                continueInForeground: false
            )
            try? store.enqueue(HanlinScriptResumeCommand(invocation: invocation))
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "HanlinScriptingWidget")
        return .result()
    }
}

@available(iOS 17.0, *)
public struct WidgetUserInteraction: AppIntent {
    public static let title: LocalizedStringResource = "User Interaction"
    public static let isDiscoverable: Bool = false

    @Parameter(title: "source")
    public var source: String?

    @Parameter(title: "target")
    public var target: String?

    @Parameter(title: "entryIndex")
    public var entryIndex: Int?

    @Parameter(title: "environmentString")
    public var environmentString: String?

    public init() {}
    public init(source: String?, target: String?, entryIndex: Int?, environmentString: String?) {
        self.source = source
        self.target = target
        self.entryIndex = entryIndex
        self.environmentString = environmentString
    }

    public func perform() async throws -> some IntentResult {
        if let source {
            WidgetCenter.shared.reloadTimelines(ofKind: source)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "HanlinScriptingWidget")
        return .result()
    }
}
