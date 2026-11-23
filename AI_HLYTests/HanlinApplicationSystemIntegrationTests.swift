import Foundation
import Testing
import UserNotifications
@testable import AI_Hanlin

@MainActor
@Suite("Original system integration host ownership")
struct HanlinApplicationSystemIntegrationTests {
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
