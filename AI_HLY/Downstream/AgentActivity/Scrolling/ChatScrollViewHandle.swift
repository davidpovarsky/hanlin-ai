import UIKit

/// Read-only access to the native transcript viewport. This is deliberately
/// non-observable: UIKit attachment/layout callbacks must not invalidate the
/// SwiftUI transcript while it is reconciling its view hierarchy.
@MainActor
final class ChatScrollViewHandle {
    private weak var scrollView: UIScrollView?
    private var boundConversationID: UUID?
    private var activeConversationID: UUID?
    private(set) var generation = UUID()
    private var deliveredGeneration: UUID?
    private var readinessTask: Task<Void, Never>?

    func bind(_ scrollView: UIScrollView?, conversationID: UUID) {
        guard self.scrollView !== scrollView || boundConversationID != conversationID else { return }
        self.scrollView = scrollView
        boundConversationID = conversationID
        generation = UUID()
        invalidateReadiness()
    }

    func activate(conversationID: UUID) {
        guard activeConversationID != conversationID else { return }
        activeConversationID = conversationID
        generation = UUID()
        invalidateReadiness()
    }

    func deactivate() {
        activeConversationID = nil
        generation = UUID()
        invalidateReadiness()
    }

    /// Attachment can finish after SwiftUI's onAppear/task/geometry callbacks.
    /// The existing native bridge calls this from its attachment and layout
    /// callbacks; deliver once after layout, with no polling or state writes
    /// inside UIKit's layout pass. Only the short-lived task owns the action.
    @discardableResult
    func whenReady(conversationID: UUID, action: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard layout(conversationID: conversationID) != nil else {
            invalidateReadiness()
            return nil
        }
        guard deliveredGeneration != generation else { return nil }
        if let readinessTask { return readinessTask }
        let expectedGeneration = generation
        readinessTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.generation == expectedGeneration else { return }
            self.readinessTask = nil
            guard self.layout(conversationID: conversationID) != nil else { return }
            self.deliveredGeneration = expectedGeneration
            action()
        }
        return readinessTask
    }

    private func invalidateReadiness() {
        readinessTask?.cancel()
        readinessTask = nil
        deliveredGeneration = nil
    }

    /// Re-read UIKit at execution time. A cached SwiftUI geometry notification
    /// can belong to the previous window, split-view width or conversation.
    func layout(conversationID: UUID) -> ChatAutoFollowLayout? {
        guard activeConversationID == conversationID,
              boundConversationID == conversationID,
              let scrollView, scrollView.window != nil else { return nil }
        let bounds = scrollView.bounds
        let content = scrollView.contentSize
        let offset = scrollView.contentOffset
        let insets = scrollView.adjustedContentInset
        guard [bounds.origin.x, bounds.origin.y, bounds.width, bounds.height,
               bounds.maxX, bounds.maxY, content.width, content.height,
               offset.x, offset.y, insets.top, insets.bottom, insets.left, insets.right]
            .allSatisfy(\.isFinite),
              bounds.width > 1, bounds.height > 1,
              content.width >= 0, content.height >= 0,
              (content.width + insets.left + insets.right).isFinite else { return nil }
        let layout = ChatAutoFollowLayout(contentHeight: Double(content.height),
            viewportHeight: Double(bounds.height), topInset: Double(insets.top),
            bottomInset: Double(insets.bottom))
        return layout.validOffsetRange == nil ? nil : layout
    }
}
