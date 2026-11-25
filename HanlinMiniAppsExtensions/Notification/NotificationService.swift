import HanlinExtensionContracts
import HanlinNotificationExtension

final class NotificationService: HanlinNotificationService, @unchecked Sendable {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .miniapps }
}
