import Foundation
import HanlinProductSplit
import Observation
import SwiftUI
import UIKit

/// Product lifecycle around the existing UI host, durable receiver and broker.
@MainActor @Observable
final class MiniAppsForegroundBridge {
    struct Presentation: Identifiable {
        let id: UUID
        let view: AnyView
    }
    var presentation: Presentation?
    var error: String?
    private(set) var returning = false
    private var opening = false
    private var admittedContext: SplitReceiverContext?

    func open(_ url: URL) async {
        guard !opening else { return }
        opening = true
        defer { opening = false }
        do {
            let id = try SplitForegroundRoute.openMiniApps.reference(in: url)
            if let presentation {
                guard presentation.id == id else { throw SplitDurabilityError.busy }
                return
            }
            let mailbox = try HanlinSplitMailbox()
            let request = try mailbox.original(id)
            guard request.issuedAt <= .now, request.expiresAt > .now else { throw SplitBridgeFailure.timedOut }
            let (item, context) = try await HanlinSplitLiveTarget.current(request)
            guard context.authorized else { throw SplitBridgeFailure.denied }
            let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
            let record = try await receiver.receive(reference: id, context: context, now: .now)
            switch record.phase {
            case .executing:
                _ = try await receiver.interrupt(reference: id, reason: .cancelled, context: context)
                throw SplitDurabilityError.outcomeUnknown
            case .outcomeUnknown: throw SplitDurabilityError.outcomeUnknown
            case .completed, .reserved: break
            }
            if case .failure? = record.outcome {
                admittedContext = context
                presentation = Presentation(id: id, view: AnyView(ContentUnavailableView(
                    "Request unavailable", systemImage: "exclamationmark.circle",
                    description: Text("Return to Hanlin to continue."))))
                return
            }
            let services = try await MiniAppsComposition.makeServices()
            admittedContext = context
            presentation = Presentation(id: id, view: try await services.launch(item))
        } catch { self.error = message(for: error) }
    }

    func cancelAndClose() async {
        guard let presentation, let context = admittedContext, !returning else { return }
        do {
            let mailbox = try HanlinSplitMailbox()
            let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
            _ = try await receiver.interrupt(reference: presentation.id, reason: .cancelled, context: context)
        } catch { self.error = message(for: error) }
        self.presentation = nil
        admittedContext = nil
    }

    func returnToOrigin() async {
        guard let presentation, !returning else { return }
        returning = true
        defer { returning = false }
        do {
            let mailbox = try HanlinSplitMailbox(), request = try mailbox.original(presentation.id)
            guard request.issuedAt <= .now, request.expiresAt > .now else { throw SplitBridgeFailure.timedOut }
            let (_, context) = try await HanlinSplitLiveTarget.current(request)
            let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
            let current = try await receiver.receive(reference: request.id, context: context, now: .now)
            switch current.phase {
            case .executing, .outcomeUnknown: throw SplitDurabilityError.outcomeUnknown
            case .completed: break
            case .reserved:
                let started = try await receiver.start(reference: request.id, context: context, now: .now)
                guard let attempt = started.attempt else { throw SplitDurabilityError.corruptState }
                let outcome: SplitBridgeOutcome
                do {
                    let response = try await HanlinMiniAppHost.shared.requestBroker.request(request.canonicalRequest())
                    outcome = try request.canonicalReturn(response).outcome
                } catch {
                    // An executor error can follow a side effect. Preserve ambiguity,
                    // never translate it into a retryable/assumed terminal success.
                    _ = try await receiver.interrupt(reference: request.id, reason: .cancelled, context: context)
                    throw SplitDurabilityError.outcomeUnknown
                }
                _ = try await receiver.complete(reference: request.id, attempt: attempt, outcome: outcome, context: context)
            }
            let url = SplitForegroundRoute.returnToAI.url(reference: presentation.id)
            let opened = await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
            guard opened else { throw SplitBridgeFailure.companionMissing }
            // Dispatch only; AI must consume the matching result and original origin.
        } catch { self.error = message(for: error) }
    }

    private func message(for error: any Error) -> String {
        if error as? SplitDurabilityError == .outcomeUnknown {
            return String(localized: "This action was interrupted. Its outcome must be checked before it can run again.")
        }
        return String(localized: "The request could not be opened or returned to Hanlin. Open Hanlin and try again.")
    }
}
