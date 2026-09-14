import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content
        content.categoryIdentifier = "CHAVRUSA_REMINDER"

        guard let value = content.userInfo["media-url"] as? String,
              let remoteURL = URL(string: value) else {
            contentHandler(content)
            return
        }
        Task {
            if let attachment = try? await attachment(from: remoteURL) {
                content.attachments = [attachment]
            }
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
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
}
