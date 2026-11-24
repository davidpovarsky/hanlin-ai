import Foundation
import Observation
import SwiftUI

enum HanlinConversationSurface: Equatable { case full, composer }

/// Share this object between the transcript and a composer placed elsewhere in
/// the host's layout. The existing endpoint bridge retains one live ChatView
/// owner and all of its original bindings, callbacks and generation checks.
@MainActor @Observable
public final class HanlinConversationPresentation {
    public let conversationID: UUID
    public var transcriptBottomInset: CGFloat = 0
    public private(set) var composerHeight: CGFloat = 0
    let context: HanlinApplicationContext
    let bridge = HanlinActiveComposerSessionBridge()

    public init(context: HanlinApplicationContext, conversationID: UUID) throws {
        _ = try context.record(conversationID)
        self.context = context
        self.conversationID = conversationID
        bridge.expectedActiveSessionID = conversationID
    }

    public var isReady: Bool { bridge.activeEndpoint?.isReadyToSend == true }
    public var isRunning: Bool { bridge.activeEndpoint?.isResponding.wrappedValue == true }
    public var draft: String {
        get { bridge.activeEndpoint?.currentMessage ?? "" }
        set { bridge.activeEndpoint?.message.wrappedValue = newValue }
    }

    @discardableResult
    public func send() -> Bool { bridge.performSendUser(expectedSessionID: conversationID) }
    @discardableResult
    public func stop() -> Bool { bridge.performCancel(expectedSessionID: conversationID) }

    func measuredComposer(_ height: CGFloat) {
        guard height.isFinite, height >= 0, abs(composerHeight - height) > 1 else { return }
        composerHeight = height
    }
}

/// The original transcript/state owner with its composer hosted through the
/// shared presentation object. Mount one transcript for each presentation.
@MainActor
public struct HanlinConversationTranscriptView: View {
    private let presentation: HanlinConversationPresentation

    public init(presentation: HanlinConversationPresentation) {
        self.presentation = presentation
    }

    public var body: some View {
        HanlinResolvedConversationView(destination: .init(conversationID: presentation.conversationID),
            externalComposerBottomInset: presentation.transcriptBottomInset)
            .environment(\.hanlinExternalCompactComposerHost, true)
            .environment(\.hanlinExternalDockHeight, presentation.composerHeight)
            .environment(\.hanlinComposerSessionBridge, presentation.bridge)
            .hanlinApplicationContext(presentation.context)
    }
}

/// Use the context initializer for an original composer with no transcript.
/// Use the presentation initializer beside HanlinConversationTranscriptView to
/// place that same conversation's composer anywhere in the host layout.
@MainActor
public struct HanlinConversationComposerView: View {
    private let context: HanlinApplicationContext
    private let conversationID: UUID
    private let presentation: HanlinConversationPresentation?
    private let availableWorkspaceSize: CGSize
    @FocusState private var inputIsActive: Bool

    public init(context: HanlinApplicationContext, conversationID: UUID,
                availableWorkspaceSize: CGSize = .zero) {
        self.context = context
        self.conversationID = conversationID
        self.presentation = nil
        self.availableWorkspaceSize = availableWorkspaceSize
    }

    public init(presentation: HanlinConversationPresentation,
                availableWorkspaceSize: CGSize = .zero) {
        self.context = presentation.context
        self.conversationID = presentation.conversationID
        self.presentation = presentation
        self.availableWorkspaceSize = availableWorkspaceSize
    }

    public var body: some View {
        Group {
            if let presentation {
                if let endpoint = presentation.bridge.activeEndpoint,
                   endpoint.sessionID == conversationID {
                    HanlinMountedComposerContent(endpoint: endpoint,
                        isInputActive: $inputIsActive,
                        availableWorkspaceSize: availableWorkspaceSize)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            presentation.measuredComposer($0)
                        }
                }
            } else {
                HanlinResolvedConversationView(destination: .init(conversationID: conversationID),
                    surface: .composer, availableComposerWorkspaceSize: availableWorkspaceSize == .zero ? nil : availableWorkspaceSize)
            }
        }
        .hanlinApplicationContext(context)
    }
}
