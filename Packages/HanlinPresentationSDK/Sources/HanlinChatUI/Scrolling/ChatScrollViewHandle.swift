#if canImport(UIKit)
import UIKit

/// Read-only access to the native transcript viewport. This is deliberately
/// non-observable: UIKit attachment/layout callbacks must not invalidate the
/// SwiftUI transcript while it is reconciling its view hierarchy.
@MainActor
public final class ChatScrollViewHandle {
    public init() {}
    private weak var scrollView: UIScrollView?
    private weak var boundWindow: UIWindow?
    private var viewport: Viewport?
    private var boundConversationID: UUID?
    private var activeConversationID: UUID?
    private weak var incomingScrollView: UIScrollView?
    private var incomingConversationID: UUID?
    public private(set) var generation = UUID()
    private var deliveredGeneration: UUID?
    private var readinessTask: Task<Void, Never>?

    /// A scroll view can move between windows or change its viewport without
    /// being replaced. Neither content size nor offset belongs here: streaming
    /// and ordinary scrolling must not create a new attachment lifetime.
    private struct Viewport: Equatable {
        let size: CGSize
        let insets: UIEdgeInsets

        @MainActor init?(_ scrollView: UIScrollView) {
            let size = scrollView.bounds.size
            let insets = scrollView.adjustedContentInset
            guard [size.width, size.height, insets.top, insets.bottom,
                   insets.left, insets.right].allSatisfy(\.isFinite),
                  size.width > 1, size.height > 1 else { return nil }
            self.size = size
            self.insets = insets
        }
    }

    public func bind(_ scrollView: UIScrollView?, conversationID: UUID) {
        // Outgoing SwiftUI representatives may dismantle after the replacement
        // conversation has activated. They do not own its native viewport.
        if let activeConversationID, activeConversationID != conversationID {
            // Conversely, make/updateUIView can precede onAppear. Stage that
            // weak binding so activation does not depend on another layout pass.
            if let scrollView {
                incomingScrollView = scrollView
                incomingConversationID = conversationID
            } else if incomingConversationID == conversationID {
                incomingScrollView = nil
                incomingConversationID = nil
            }
            return
        }
        guard self.scrollView !== scrollView || boundConversationID != conversationID else {
            refreshViewport()
            return
        }
        self.scrollView = scrollView
        boundConversationID = conversationID
        boundWindow = scrollView?.window
        viewport = scrollView.flatMap { Viewport($0) }
        generation = UUID()
        invalidateReadiness()
    }

    public func activate(conversationID: UUID) {
        guard activeConversationID != conversationID else { return }
        activeConversationID = conversationID
        generation = UUID()
        invalidateReadiness()
        if incomingConversationID == conversationID {
            let incoming = incomingScrollView
            incomingScrollView = nil
            incomingConversationID = nil
            bind(incoming, conversationID: conversationID)
        }
    }

    @discardableResult
    public func deactivate(conversationID: UUID? = nil) -> Bool {
        if let conversationID, activeConversationID != conversationID { return false }
        activeConversationID = nil
        generation = UUID()
        invalidateReadiness()
        return true
    }

    /// Attachment can finish after SwiftUI's onAppear/task/geometry callbacks.
    /// The existing native bridge calls this from its attachment and layout
    /// callbacks; deliver once after layout, with no polling or state writes
    /// inside UIKit's layout pass. Only the short-lived task owns the action.
    @discardableResult
    public func whenReady(conversationID: UUID, action: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard activeConversationID == conversationID, boundConversationID == conversationID else { return nil }
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
            guard self.layout(conversationID: conversationID,
                              expectedGeneration: expectedGeneration) != nil else { return }
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

    private func refreshViewport() {
        let currentWindow = scrollView?.window
        let currentViewport = scrollView.flatMap { Viewport($0) }
        guard boundWindow !== currentWindow || viewport != currentViewport else { return }
        boundWindow = currentWindow
        viewport = currentViewport
        generation = UUID()
        invalidateReadiness()
    }

    /// Read the settled offset from the same attached viewport used to admit
    /// scrolling. In particular, scroll-idle and reattachment must not reuse a
    /// Boolean delivered before the native scroll view finished its layout.
    public func position(conversationID: UUID, expectedGeneration: UUID? = nil) -> ChatAutoFollowPosition? {
        guard let layout = layout(conversationID: conversationID, expectedGeneration: expectedGeneration),
              let scrollView else { return nil }
        let position = ChatAutoFollowPosition(layout: layout, contentOffsetY: Double(scrollView.contentOffset.y))
        return position.isNearBottom == nil ? nil : position
    }

    /// Re-read UIKit at execution time. A cached SwiftUI geometry notification
    /// can belong to the previous window, split-view width or conversation.
    public func layout(conversationID: UUID, expectedGeneration: UUID? = nil) -> ChatAutoFollowLayout? {
        guard activeConversationID == conversationID,
              boundConversationID == conversationID else { return nil }
        // Refresh before comparing the request generation. Checking generation
        // first accepts a stale request when UIKit changed bounds/window before
        // its next bridge callback.
        refreshViewport()
        guard expectedGeneration == nil || expectedGeneration == generation,
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

#endif
