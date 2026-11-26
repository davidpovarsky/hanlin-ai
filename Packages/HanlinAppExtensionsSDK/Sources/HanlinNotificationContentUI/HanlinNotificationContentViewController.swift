#if canImport(UIKit) && canImport(UserNotificationsUI)
import Foundation
import HanlinExtensionContracts
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinTranslationUI
import SwiftUI
import UIKit
@preconcurrency import UserNotifications
@preconcurrency import UserNotificationsUI

/// Notification content is a prepared original presentation. The existing
/// notification event remains the sole envelope for its foreground Host action.
@MainActor
open class HanlinNotificationContentViewController: UIViewController, UNNotificationContentExtension {
    open var hostConfiguration: HanlinExtensionHostConfiguration { .init() }

    private let model = HanlinNotificationContentModel()
    private var hosting: UIHostingController<HanlinNotificationContentRoot>?
    private var payload: HanlinNotificationPresentationPayload?
    private var continuation: HanlinNotificationEvent?
    private var receivedNotification: UNNotification?
    private var notificationRequestID: String?
    private var sessionID = UUID()

    open override func viewDidLoad() {
        super.viewDidLoad()
        let root = HanlinNotificationContentRoot(model: model,
            retry: { [weak self] in
                guard let self, let notification = self.receivedNotification else { return }
                self.didReceive(notification)
            },
            effect: { [weak self] effect, request in self?.apply(effect, request: request) })
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hosting = host
    }

    open func didReceive(_ notification: UNNotification) {
        loadViewIfNeeded()
        receivedNotification = notification
        if notificationRequestID != notification.request.identifier {
            sessionID = UUID()
            notificationRequestID = notification.request.identifier
        }
        model.error = nil
        model.receiptStatus = nil
        model.request = nil
        payload = nil
        continuation = nil
        do {
            let configuration = hostConfiguration
            guard let category = configuration.notificationCategoryIdentifier,
                  category == notification.request.content.categoryIdentifier else {
                throw HanlinNativePresentationError.invalidRequest
            }
            guard let selected = try HanlinNotificationPresentationPayload.decode(
                userInfo: notification.request.content.userInfo) else {
                // This category also carries ordinary reminders. Preserve
                // their system title/body/actions without inventing a MiniApp.
                preferredContentSize = CGSize(width: view.bounds.width, height: 1)
                return
            }
            let event = try HanlinNotificationEvent.decode(userInfo: notification.request.content.userInfo)
            if let event { try selected.validateContinuation(event) }
            let store = try HanlinScriptExtensionStore(hostConfiguration: configuration)
            guard let snapshot = try store.loadReadOnly() else {
                throw HanlinNativePresentationError.unavailable
            }
            let request = try selected.request(sessionID: sessionID)
            _ = try HanlinNativePresentationExecutor.descriptor(for: request, in: snapshot)
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw HanlinNativePresentationError.unavailable
            }
            payload = selected
            continuation = event
            model.store = store
            model.storage = .extensionLocal(root: support.appendingPathComponent(
                "HanlinNotificationPresentations", isDirectory: true))
            model.request = request
            model.displayName = snapshot.nativePresentations.first {
                $0.kind == .notificationUI && $0.identity == selected.identity
            }?.displayName ?? "MiniApp"
            if let event, let receipt = try store.receipt(for: event.id) {
                model.receiptStatus = receipt.status.rawValue
            }
            preferredContentSize = CGSize(width: view.bounds.width, height: 360)
        } catch {
            model.error = error.localizedDescription
            preferredContentSize = CGSize(width: view.bounds.width, height: 160)
        }
    }

    /// A system notification action forwards only after the matching exact
    /// event was persisted. A queued receipt is displayed as queued, not done.
    open func didReceive(_ response: UNNotificationResponse,
                         completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            completion(.dismiss)
            return
        }
        do {
            // The system can deliver a response before a presentation pass.
            if notificationRequestID != response.notification.request.identifier {
                didReceive(response.notification)
            }
            if let error = model.error { throw HanlinNotificationContentError(message: error) }
            try enqueueContinuationIfPresent()
            completion(.dismissAndForwardAction)
        } catch {
            model.error = error.localizedDescription
            completion(.doNotDismiss)
        }
    }

    private func apply(_ effect: HanlinNativePresentationEffect, request: HanlinNativePresentationRequest) {
        guard request == model.request, request.kind == .notificationUI else { return }
        do {
            try effect.validate(for: request)
            switch effect.notificationAction {
            case .openApp:
                try enqueueContinuationIfPresent()
                extensionContext?.performNotificationDefaultAction()
            case .dismiss:
                extensionContext?.dismissNotificationContentExtension()
            case nil:
                break
            }
        } catch {
            model.error = error.localizedDescription
        }
    }

    private func enqueueContinuationIfPresent() throws {
        guard let payload, let continuation else { return }
        guard let store = model.store else { throw HanlinNativePresentationError.unavailable }
        let receipt = try payload.enqueueContinuation(continuation, in: store)
        model.receiptStatus = receipt.status.rawValue
    }
}

private struct HanlinNotificationContentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
private final class HanlinNotificationContentModel: ObservableObject {
    @Published var request: HanlinNativePresentationRequest?
    @Published var store: HanlinScriptExtensionStore?
    @Published var storage: HanlinNativePresentationStorage = .shared
    @Published var displayName = "MiniApp"
    @Published var error: String?
    @Published var receiptStatus: String?
}

@MainActor
private struct HanlinNotificationContentRoot: View {
    @ObservedObject var model: HanlinNotificationContentModel
    let retry: () -> Void
    let effect: (HanlinNativePresentationEffect, HanlinNativePresentationRequest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let request = model.request, let store = model.store {
                    Text(model.displayName).font(.headline)
                    HanlinNativePresentationContentView(request: request, store: store, storage: model.storage) {
                        effect($0, request)
                    }
                    .accessibilityIdentifier("hanlin.notification.presentation")
                }
                if let error = model.error {
                    Label("MiniApp notification unavailable", systemImage: "exclamationmark.triangle")
                    Text(error).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("hanlin.notification.error")
                    Button("Try again", action: retry)
                }
                if let status = model.receiptStatus {
                    Text("Action status: \(status)").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("hanlin.notification.receipt")
                }
            }
            .padding(model.request == nil && model.error == nil ? 0 : 12)
        }
    }
}
#endif
