import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let stateLock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        content.categoryIdentifier = "CHAVRUSA_REMINDER"
        stateLock.withLock {
            self.contentHandler = contentHandler
            bestAttemptContent = content
        }

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

    override func serviceExtensionTimeWillExpire() {
        deliverBestAttempt()
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
