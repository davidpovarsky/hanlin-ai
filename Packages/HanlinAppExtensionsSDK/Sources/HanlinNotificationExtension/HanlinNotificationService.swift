import HanlinExtensionContracts
import Foundation
import HanlinScriptExtensions
import OSLog
import UserNotifications

open class HanlinNotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let suppliedConfiguration: HanlinExtensionHostConfiguration?

    open var hostConfiguration: HanlinExtensionHostConfiguration {
        suppliedConfiguration ?? .init()
    }

    public override init() {
        self.suppliedConfiguration = nil
        super.init()
    }

    public init(configuration: HanlinExtensionHostConfiguration) {
        self.suppliedConfiguration = configuration
        super.init()
    }

    private static let logger = Logger(subsystem: "com.hanlin.ai", category: "NotificationIngress")
    private let stateLock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    open override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        if let category = hostConfiguration.notificationCategoryIdentifier {
            content.categoryIdentifier = category
        }
        stateLock.withLock {
            self.contentHandler = contentHandler
            bestAttemptContent = content
        }

        persistMiniAppEvent(in: content)

        guard let value = content.userInfo["media-url"] as? String,
              let remoteURL = URL(string: value) else {
            deliverBestAttempt()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if let attachment = try? await self.attachment(from: remoteURL) {
                self.stateLock.withLock {
                    self.bestAttemptContent?.attachments = [attachment]
                }
            }
            self.deliverBestAttempt()
        }
    }

    open override func serviceExtensionTimeWillExpire() {
        deliverBestAttempt()
    }

    private func persistMiniAppEvent(in content: UNMutableNotificationContent) {
        guard content.userInfo[HanlinNotificationEvent.userInfoKey] != nil else { return }
        let delivery: [String: String]
        do {
            guard let event = try HanlinNotificationEvent.decode(userInfo: content.userInfo) else { return }
            let store = try HanlinScriptExtensionStore(hostConfiguration: hostConfiguration)
            let receipt = try HanlinNotificationInvocation.enqueue(event, in: store)
            delivery = ["invocationID": receipt.invocationID.uuidString.lowercased(),
                        "status": receipt.status.rawValue]
        } catch {
            let reason: String
            switch error {
            case HanlinInvocationQueueError.duplicateIdentity: reason = "duplicateIdentity"
            case HanlinInvocationQueueError.invalidEnvelope, is DecodingError: reason = "invalidEnvelope"
            case let failure as HanlinInvocationDispatchError: reason = failure.failure.rawValue
            default: reason = "storageUnavailable"
            }
            // An ingress rejection is not an invented action-result receipt.
            delivery = ["ingressStatus": "rejected", "reason": reason]
            Self.logger.error("notification_event_rejected: \(reason, privacy: .public)")
        }
        stateLock.withLock {
            bestAttemptContent?.userInfo[HanlinNotificationEvent.deliveryInfoKey] = delivery
        }
    }

    private func attachment(from remoteURL: URL) async throws -> UNNotificationAttachment {
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        let suggestedName = response.suggestedFilename ?? remoteURL.lastPathComponent
        let destination = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension((suggestedName as NSString).pathExtension)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return try UNNotificationAttachment(identifier: "media", url: destination)
    }

    private func deliverBestAttempt() {
        let delivery = stateLock.withLock {
            let delivery = (contentHandler, bestAttemptContent)
            contentHandler = nil
            bestAttemptContent = nil
            return delivery
        }

        guard let contentHandler = delivery.0, let bestAttemptContent = delivery.1 else { return }
        contentHandler(bestAttemptContent)
    }
}
