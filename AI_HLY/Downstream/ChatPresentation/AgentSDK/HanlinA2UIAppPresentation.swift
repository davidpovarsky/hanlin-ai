#if HANLIN_A2UI_POC
import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import Observation
import SwiftUI

/// Strongly retained by the existing ChatView; the SDK owner holds only its weak protocol seam.
/// All mutations occur in owner callbacks or explicit UI lifecycle, never in View.body.
@MainActor @Observable
final class HanlinA2UIAppPresentation: HanlinAppAgentPresentationConsumer {
    struct PendingAction {
        let request: HanlinHostInteractionRequest
        let key: HanlinA2UIResultKey
        let binding: HanlinAppAgentRowBinding
    }
    enum BindingError: Error, Equatable { case mismatch, ambiguous, resourceLimit }
    private struct Row: Hashable { let rowID: UUID; let uiRunID: UUID }

    private var live: HanlinA2UIAgentPresentationAdapter?
    private var history: HanlinA2UIAgentPresentationAdapter?
    private var rows: [Row: HanlinAppAgentRowBinding] = [:]
    private var historicalRows: Set<Row> = []
    private(set) var pendingAction: PendingAction?
    @ObservationIgnored private weak var session: HanlinAgentSession?

    func installed(session: HanlinAgentSession) {
        guard self.session !== session else { return }
        if let previous = live?.identity,
           previous.conversationID != session.identity.conversationID || previous.context.namespace != session.identity.context.namespace {
            if let history { history.invalidate(history.identity) }
            history = nil; rows = [:]; historicalRows = []
        }
        if let live { live.invalidate(live.identity) }
        pendingAction = nil
        self.session = session
        live = HanlinA2UIAgentPresentationAdapter(session: session) { [weak self] request, key in
            self?.enqueue(request, key: key)
        }
    }

    func validateCompleteParts(_ parts: [HanlinChatStructuredPart]) throws {
        try HanlinA2UICompleteBatchValidator.validate(parts)
    }

    func receive(_ event: HanlinAgentEvent, binding: HanlinAppAgentRowBinding) throws {
        guard binding.session == event.session, binding.canonicalRunID == event.runID,
              binding.reference.messageID == binding.reference.rowID,
              session?.identity == binding.session, live?.identity == binding.session else { throw BindingError.mismatch }
        if case .structuredPart(let part) = event.event {
            guard part.messageID == binding.reference.messageID else { throw BindingError.mismatch }
        }
        let row = Row(rowID: binding.reference.rowID, uiRunID: binding.reference.uiRunID)
        if let previous = rows[row], previous != binding { throw BindingError.ambiguous }
        guard !rows.values.contains(where: {
            $0.canonicalRunID == binding.canonicalRunID && $0 != binding
        }) else { throw BindingError.ambiguous }
        guard rows[row] != nil || rows.count < 256 else { throw BindingError.resourceLimit }
        rows[row] = binding
        _ = try live?.receive(event)
    }

    func completed(_ completion: HanlinAgentRunCompletion) {
        guard live?.identity == completion.session else { return }
        live?.completed(completion)
    }

    func invalidated(_ original: HanlinHostSession) {
        guard live?.identity == original else { return }
        pendingAction = nil
        live?.invalidate(original)
    }

    func producerStreamDrained(runID: UUID) { _ = live?.producerStreamDrained(runID: runID) }

    func replay(_ record: HanlinConversationRecord, bindings: [HanlinAppAgentRowBinding]) throws {
        try record.validate()
        var restored: [Row: HanlinAppAgentRowBinding] = [:]
        var combined = rows
        for binding in bindings {
            guard binding.session.conversationID == record.conversationID,
                  binding.session.context.namespace == record.namespace,
                  binding.reference.messageID == binding.reference.rowID else { throw BindingError.mismatch }
            let row = Row(rowID: binding.reference.rowID, uiRunID: binding.reference.uiRunID)
            if let previous = restored[row], previous != binding { throw BindingError.ambiguous }
            if let previous = combined[row], previous != binding { throw BindingError.ambiguous }
            guard !combined.values.contains(where: {
                $0.canonicalRunID == binding.canonicalRunID && $0 != binding
            }) else { throw BindingError.ambiguous }
            restored[row] = binding
            combined[row] = binding
        }
        guard combined.count <= 256 else { throw BindingError.resourceLimit }
        // A separate bounded reader leaves the live adapter's run budget available for new
        // turns. Older history retains the existing Markdown fallback and canonical storage.
        let recent = Array(bindings.suffix(HanlinA2UIContentLimits.maximumRuns))
        let reader = recent.last.map { HanlinA2UIAgentPresentationAdapter(readOnly: $0.session) }
        var committed = false
        defer { if !committed, let reader { reader.invalidate(reader.identity) } }
        var visible: Set<Row> = []
        for binding in recent {
            try reader?.replay(record, runID: binding.canonicalRunID, messageID: binding.reference.messageID)
            visible.insert(Row(rowID: binding.reference.rowID, uiRunID: binding.reference.uiRunID))
        }
        if let history { history.invalidate(history.identity) }
        history = reader
        historicalRows = visible
        rows = combined
        committed = true
    }

    func projection(uiRunID: UUID?, rowID: UUID, text: String) -> HanlinChatContentProjection? {
        guard let uiRunID, let binding = rows[Row(rowID: rowID, uiRunID: uiRunID)] else { return nil }
        if live?.identity == binding.session,
           let result = live?.source?.projection(runID: binding.canonicalRunID,
                                                messageID: binding.reference.messageID, text: text) { return result }
        guard historicalRows.contains(Row(rowID: rowID, uiRunID: uiRunID)) else { return nil }
        return history?.source?.projection(runID: binding.canonicalRunID, messageID: binding.reference.messageID, text: text)
    }

    func hasStructuredContent(uiRunID: UUID, rowID: UUID, text: String) -> Bool {
        projection(uiRunID: uiRunID, rowID: rowID, text: text)?.parts.contains {
            switch $0.content { case .surface, .unavailable: true; case .markdown: false }
        } == true
    }

    /// Select the existing original row for the APIManager's text fallback. This is an
    /// immutable identity lookup; it neither reconstructs nor produces that fallback text.
    func hasCanonicalParts(uiRunID: UUID, rowID: UUID) -> Bool {
        let row = Row(rowID: rowID, uiRunID: uiRunID)
        guard let binding = rows[row] else { return false }
        if live?.identity == binding.session,
           live?.source?.registeredProjection(runID: binding.canonicalRunID, messageID: binding.reference.messageID) != nil { return true }
        return historicalRows.contains(row)
            && history?.source?.registeredProjection(runID: binding.canonicalRunID, messageID: binding.reference.messageID) != nil
    }

    func isCurrent(_ action: PendingAction) -> Bool {
        let binding = action.binding
        return rows[Row(rowID: binding.reference.rowID, uiRunID: binding.reference.uiRunID)] == binding
            && session?.identity == binding.session && action.request.origin.session == binding.session
            && action.request.origin.runID == binding.canonicalRunID
            && action.request.origin.messageID == binding.reference.messageID
            && action.key.runID == binding.canonicalRunID
            && action.key.origin == .model(messageID: binding.reference.messageID)
            && action.key.resultID == action.request.origin.partID
            && live?.store.projection(for: action.key)?.isReceivingFinished == true
            && live?.isCurrent(action.key) == true
    }

    func takePendingAction() -> PendingAction? {
        guard let action = pendingAction else { return nil }
        pendingAction = nil
        return isCurrent(action) ? action : nil
    }

    func discard(_ action: PendingAction) {
        guard isCurrent(action) else { return }
        _ = live?.discard(action.key)
        if pendingAction?.key == action.key { pendingAction = nil }
    }

    private func enqueue(_ request: HanlinHostInteractionRequest, key: HanlinA2UIResultKey) {
        guard pendingAction == nil,
              let binding = rows.values.first(where: {
                  $0.session == request.origin.session && $0.canonicalRunID == request.origin.runID
                      && $0.reference.messageID == request.origin.messageID
              }) else { return }
        let action = PendingAction(request: request, key: key, binding: binding)
        guard isCurrent(action) else { return }
        pendingAction = action
    }
}

extension EnvironmentValues {
    @Entry var hanlinA2UIAppPresentation: HanlinA2UIAppPresentation? = nil
}
#endif
