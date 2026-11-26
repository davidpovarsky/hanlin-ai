import HanlinExtensionContracts
import HanlinNotificationContentUI

@MainActor
final class NotificationViewController: HanlinNotificationContentViewController {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .hanlin }
}
