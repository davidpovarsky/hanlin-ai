import Foundation

/// Coalesces only adjacent plain deltas. Tool/approval/source/error/round events
/// flush immediately and retain their exact order. The first delta is immediate;
/// a fixed deadline delivers the tail even when the provider becomes silent.
@MainActor
final class HanlinChatStreamBuffer {
    private enum Kind: Equatable { case answer, reasoning }
    private var pending: StreamData?
    private var pendingKind: Kind?
    private var scheduledFlush: Task<Void, Never>?
    private var lastPublication: ContinuousClock.Instant?
    private let interval: Duration
    private let publish: @MainActor (StreamData) -> Void

    init(interval: Duration = .milliseconds(50),
         publish: @escaping @MainActor (StreamData) -> Void) {
        self.interval = interval
        self.publish = publish
    }

    func append(_ data: StreamData) {
        guard let kind = Self.plainDeltaKind(data) else {
            flush()
            lastPublication = .now
            publish(data)
            return
        }
        if pendingKind != kind { flush() }
        if var buffered = pending {
            switch kind {
            case .answer: buffered.content = (buffered.content ?? "") + (data.content ?? "")
            case .reasoning: buffered.reasoning = (buffered.reasoning ?? "") + (data.reasoning ?? "")
            }
            pending = buffered
        } else {
            pending = data
            pendingKind = kind
        }
        let now = ContinuousClock.now
        guard let lastPublication, now - lastPublication < interval else {
            flush()
            return
        }
        // Never restart the deadline for another token (no trailing debounce).
        guard scheduledFlush == nil else { return }
        let delay = interval - (now - lastPublication)
        scheduledFlush = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard let data = pending else { return }
        pending = nil
        pendingKind = nil
        lastPublication = .now
        publish(data)
    }

    /// Cancellation must not publish a stale run into a replacement conversation.
    func cancel() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pending = nil
        pendingKind = nil
    }

    private static func plainDeltaKind(_ data: StreamData) -> Kind? {
        guard data.toolContent == nil, data.toolName == nil,
              data.resources == nil, data.searchEngine == nil,
              data.image_content == nil, data.image_text == nil,
              data.audioContent == nil, data.document_text == nil,
              data.search_text == nil, data.searchQueries == nil,
              data.locations_info == nil, data.route_info == nil,
              data.events == nil, data.htmlContent == nil,
              data.health_info == nil, data.code_info == nil,
              data.knowledge_card == nil, data.audioAsset == nil,
              data.autoTitle == nil, data.errorInfo == nil,
              data.operationalState == nil, data.operationalDescription == nil,
              data.splitMarkers == nil, data.canvas_info == nil,
              data.agentEvents.isEmpty, data.modelRoundID == nil else { return nil }
        if data.content != nil, data.reasoning == nil { return .answer }
        if data.reasoning != nil, data.content == nil { return .reasoning }
        return nil
    }
}
