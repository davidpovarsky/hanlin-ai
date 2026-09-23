import Foundation
import HanlinPlatformContracts
import SwiftUI

/// Lifecycle protocol for an active embedded result surface hosted in chat.
@MainActor
public protocol HanlinEmbeddedResultSession: AnyObject, Sendable {
    var sessionID: UUID { get }
    var engine: HanlinMiniAppEngine { get }
    var appID: HanlinAppID? { get }
    var rootView: AnyView { get }
    func tearDown()
}

/// Generic container for an embedded result session.
@MainActor
public final class AnyEmbeddedResultSession: HanlinEmbeddedResultSession {
    public let sessionID: UUID
    public let engine: HanlinMiniAppEngine
    public let appID: HanlinAppID?
    private let _rootView: AnyView
    private let onTearDown: (@MainActor () -> Void)?

    public var rootView: AnyView {
        _rootView
    }

    public init(
        sessionID: UUID = UUID(),
        engine: HanlinMiniAppEngine,
        appID: HanlinAppID? = nil,
        rootView: AnyView,
        onTearDown: (@MainActor () -> Void)? = nil
    ) {
        self.sessionID = sessionID
        self.engine = engine
        self.appID = appID
        self._rootView = rootView
        self.onTearDown = onTearDown
    }

    public func tearDown() {
        onTearDown?()
    }

    deinit {
        // Safe cleanup on dealloc
    }
}
