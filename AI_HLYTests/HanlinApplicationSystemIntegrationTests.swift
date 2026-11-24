import Foundation
import Testing
import UserNotifications
import HanlinWidgetUI
@testable import AI_Hanlin

@MainActor
@Suite("Original system integration host ownership")
struct HanlinApplicationSystemIntegrationTests {
    @Test(arguments: ["en", "he", "zh-Hans"])
    func widgetIntentMetadataLoadsTheOriginalHostTranslations(language: String) throws {
        let expected: [String: [String]] = [
            "en": ["Run Script Action", "Widget instance", "Action", "Input"],
            "he": ["הפעלת פעולת סקריפט", "מופע וידג׳ט", "פעולה", "קלט"],
            "zh-Hans": ["运行脚本操作", "小组件实例", "操作", "输入"]
        ]
        let values = try #require(expected[language])
        var action = HanlinRunScriptActionIntent.title
        var widget = HanlinWidgetConfigurationIntent.title
        action.locale = Locale(identifier: language)
        widget.locale = Locale(identifier: language)
        #expect(action.table == "HanlinAppIntents")
        #expect(widget.table == "HanlinAppIntents")
        #expect(String(localized: action) == values[0])
        #expect(String(localized: widget) == values[1])

        // Both actual executables must carry the same generated host table.
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let widgetBundle = try #require(Bundle(url: plugins.appending(path: "HanlinScriptingWidgets.appex")))
        for bundle in [Bundle.main, widgetBundle] {
            let url = try #require(bundle.url(forResource: language, withExtension: "lproj"))
            let localized = try #require(Bundle(url: url))
            for (key, value) in zip(["Run Script Action", "Widget instance", "Action", "Input"], values) {
                #expect(localized.localizedString(forKey: key, value: nil, table: "HanlinAppIntents") == value)
            }
        }
    }

    @Test
    func notificationBootstrapPreservesHostActionsAndCategories() throws {
        let action = UNNotificationAction(identifier: "HOST_REPLY", title: "Reply", options: [])
        let host = UNNotificationCategory(identifier: "HOST_MESSAGES", actions: [action],
            intentIdentifiers: ["host.intent"], options: [.customDismissAction])
        let merged = ChavrusaSystemIntegrationBootstrap.categories([host], adding: "SDK_REMINDER")
        #expect(merged.count == 2)
        let retained = try #require(merged.first(where: { $0.identifier == "HOST_MESSAGES" }))
        #expect(retained.actions.map(\.identifier) == ["HOST_REPLY"])
        #expect(retained.intentIdentifiers == ["host.intent"])
        let collision = ChavrusaSystemIntegrationBootstrap.categories([host], adding: "HOST_MESSAGES")
        #expect(collision.count == 1)
        #expect(collision.first?.actions.map(\.identifier) == ["HOST_REPLY"])
    }

    @Test
    func plainHostsDoNotInheritHanlinShareGroupOrCameraRoute() throws {
        let host = HanlinApplicationConfiguration(appIdentifier: "com.example.host")
        #expect(host.systemIntegrations.shareAppGroupIdentifier == nil)
        #expect(host.systemIntegrations.notificationCategoryIdentifier == nil)
        #expect(host.systemIntegrations.visionURL == nil)
        let hanlinURL = try #require(URL(string: "chavrusachat://openVisionView"))
        #expect(!host.systemIntegrations.isVisionURL(hanlinURL))
        #expect(HanlinApplicationConfiguration.hanlin.systemIntegrations.isVisionURL(hanlinURL))
        let ownURL = try #require(URL(string: "reader://assistant/camera"))
        let own = HanlinApplicationSystemIntegrations(shareAppGroupIdentifier: "group.com.example.reader",
            notificationCategoryIdentifier: "READER_REMINDER", visionURL: ownURL)
        #expect(own.isVisionURL(ownURL))
        #expect(!own.isVisionURL(hanlinURL))
        #expect(!own.isVisionURL(try #require(URL(string: "reader://assistant/settings"))))
    }

    @Test
    func liveSystemIntegrationOwnershipCannotBeRedirected() throws {
        let owner = HanlinApplicationProcessRuntime()
        let container = NSObject()
        let runtime = HanlinApplicationRuntimeConfiguration(
            directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            mcpSecretService: "synthetic.mcp", environmentSecretService: "synthetic.runtime")
        let first = HanlinApplicationSystemIntegrations(shareAppGroupIdentifier: "group.com.example.first")
        let second = HanlinApplicationSystemIntegrations(shareAppGroupIdentifier: "group.com.example.second")
        try owner.install(runtime, modelContainer: container, systemIntegrations: first)
        #expect(throws: HanlinApplicationError.self) {
            try owner.install(runtime, modelContainer: container, systemIntegrations: second)
        }
        #expect(owner.systemIntegrations == first)
    }
}
