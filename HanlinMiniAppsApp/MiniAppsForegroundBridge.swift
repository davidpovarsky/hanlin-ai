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
    /// Privacy-safe static stage and error-category code for the latest failure.
    /// Never includes request IDs, payloads, URLs, or App Group paths.
    private(set) var lastFailureCode: String?
    private(set) var returning = false
    private var opening = false
    private var admittedContext: SplitReceiverContext?

    func open(_ url: URL) async {
        guard !opening else { return }
        opening = true
        error = nil
        lastFailureCode = nil
        defer { opening = false }
        var stage = "open_route"
        do {
            let id = try SplitForegroundRoute.openMiniApps.reference(in: url)
            if let presentation {
                guard presentation.id == id else { throw SplitDurabilityError.busy }
                return
            }
            stage = "open_mailbox"
            let mailbox = try HanlinSplitMailbox()
            let request = try mailbox.original(id)
            stage = "open_expiry"
            guard request.issuedAt <= .now, request.expiresAt > .now else { throw SplitBridgeFailure.timedOut }
            stage = "open_target"
            let (item, context) = try await HanlinSplitLiveTarget.current(request)
            guard context.authorized else { throw SplitBridgeFailure.denied }
            stage = "open_receive"
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
            stage = "open_launch"
            let provider = HanlinMiniAppsProvider()
            admittedContext = context
            presentation = Presentation(id: id, view: try await provider.launch(item, includesDismissControl: false))
        } catch {
            recordFailure(stage: stage, error: error)
        }
    }

    func cancelAndClose(openURL: (@MainActor (URL) async -> Bool)? = nil) async {
        guard let presentation, let context = admittedContext, !returning else { return }
        returning = true
        error = nil
        lastFailureCode = nil
        defer { returning = false }
        var stage = "cancel_interrupt"
        do {
            let mailbox = try HanlinSplitMailbox()
            let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
            let cancelled = try await receiver.interrupt(reference: presentation.id, reason: .cancelled, context: context)
            guard cancelled.phase == .completed else { throw SplitDurabilityError.outcomeUnknown }
            // Cancellation is an original terminal receipt too. Wake the saved
            // origin immediately; don't leave its Host invocation waiting on a
            // timer. Keep this view on failure so the persisted receipt can retry.
            stage = "cancel_return_url"
            try await returnURL(reference: presentation.id, openURL: openURL)
            self.presentation = nil
            admittedContext = nil
        } catch {
            recordFailure(stage: stage, error: error)
        }
    }

    func returnToOrigin(openURL: (@MainActor (URL) async -> Bool)? = nil) async {
        guard let presentation, !returning else { return }
        returning = true
        error = nil
        lastFailureCode = nil
        defer { returning = false }
        var stage = "return_mailbox"
        do {
            let mailbox = try HanlinSplitMailbox(), request = try mailbox.original(presentation.id)
            stage = "return_expiry"
            guard request.issuedAt <= .now, request.expiresAt > .now else { throw SplitBridgeFailure.timedOut }
            stage = "return_target"
            let (_, context) = try await HanlinSplitLiveTarget.current(request)
            guard context.authorized else { throw SplitBridgeFailure.denied }
            stage = "return_receive"
            let receiver = SplitDurableReceiver(persistence: mailbox, source: mailbox)
            let current = try await receiver.receive(reference: request.id, context: context, now: .now)
            switch current.phase {
            case .executing, .outcomeUnknown: throw SplitDurabilityError.outcomeUnknown
            case .completed: break
            case .reserved:
                stage = "return_start"
                let started = try await receiver.start(reference: request.id, context: context, now: .now)
                guard let attempt = started.attempt else { throw SplitDurabilityError.corruptState }
                stage = "return_execute"
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
                stage = "return_complete"
                _ = try await receiver.complete(reference: request.id, attempt: attempt, outcome: outcome, context: context)
            }
            stage = "return_url"
            try await returnURL(reference: presentation.id, openURL: openURL)
            self.presentation = nil
            admittedContext = nil
            // Dispatch only; AI must consume the matching result and original origin.
        } catch {
            recordFailure(stage: stage, error: error)
        }
    }

    private func returnURL(reference: UUID, openURL: (@MainActor (URL) async -> Bool)? = nil) async throws {
        let url = SplitForegroundRoute.returnToAI.url(reference: reference)
        let opened: Bool
        if let openURL {
            opened = await openURL(url)
        } else {
            opened = await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
        }
        guard opened else { throw SplitBridgeFailure.companionMissing }
    }

    private func recordFailure(stage: String, error: any Error) {
        let code = "\(stage):\(errorCategory(for: error))"
        lastFailureCode = code
        self.error = message(for: error)
        print("[MiniAppsForegroundBridge] failure \(code)")
    }

    private func errorCategory(for error: any Error) -> String {
        switch error {
        case SplitBridgeFailure.timedOut: return "timed_out"
        case SplitBridgeFailure.denied: return "denied"
        case SplitBridgeFailure.outOfOrder: return "out_of_order"
        case SplitBridgeFailure.correlationMismatch: return "correlation_mismatch"
        case SplitBridgeFailure.companionMissing: return "companion_missing"
        case SplitBridgeFailure.transportUnavailable: return "transport_unavailable"
        case SplitBridgeFailure.unsupportedRoute: return "unsupported_route"
        case SplitBridgeFailure.duplicate: return "duplicate"
        case SplitBridgeFailure.cancelled: return "cancelled"
        case SplitBridgeFailure.malformed: return "malformed"
        case SplitBridgeFailure.oversized: return "oversized"
        case SplitBridgeFailure.expired: return "expired"
        case SplitBridgeFailure.staleGeneration: return "stale_generation"
        case SplitBridgeFailure.capacityExceeded: return "capacity_exceeded"
        case SplitBridgeFailure.offline: return "offline"
        case SplitDurabilityError.outcomeUnknown: return "outcome_unknown"
        case SplitDurabilityError.busy: return "busy"
        case SplitDurabilityError.corruptState: return "corrupt_state"
        case SplitDurabilityError.unsupportedVersion: return "unsupported_version"
        case SplitDurabilityError.attemptMismatch: return "attempt_mismatch"
        case SplitDurabilityError.recoveryConflict: return "recovery_conflict"
        case SplitDurabilityError.persistenceUnavailable: return "persistence_unavailable"
        case SplitDurabilityError.interrupted: return "interrupted"
        case SplitDurabilityError.encodedSizeExceeded: return "encoded_size_exceeded"
        default: return "other"
        }
    }

    private func message(for error: any Error) -> String {
        if error as? SplitDurabilityError == .outcomeUnknown {
            return String(localized: "This action was interrupted. Its outcome must be checked before it can run again.")
        }
        return String(localized: "The request could not be opened or returned to Hanlin. Open Hanlin and try again.")
    }
}
