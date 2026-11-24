import HanlinExtensionContracts
import HanlinNotificationExtension

/// The OS principal class retains the original notification category policy.
final class NotificationService: HanlinNotificationService, @unchecked Sendable {
    override var hostConfiguration: HanlinExtensionHostConfiguration { .hanlin }
}
