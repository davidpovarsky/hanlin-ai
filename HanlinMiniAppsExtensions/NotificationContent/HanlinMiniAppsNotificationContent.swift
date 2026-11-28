import HanlinExtensionContracts
import HanlinNotificationContentUI

@MainActor
final class HanlinMiniAppsNotificationContent: HanlinNotificationContentViewController {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .miniapps }
}
