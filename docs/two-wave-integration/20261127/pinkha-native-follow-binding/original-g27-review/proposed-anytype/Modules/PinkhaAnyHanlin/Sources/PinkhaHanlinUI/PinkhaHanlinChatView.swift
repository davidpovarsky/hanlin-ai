#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinChatUI
import HanlinScriptUI
import HanlinPresentationKit

/// Layout composition only. Message rendering, input and send control are canonical Hanlin UI.
public struct PinkhaHanlinChatView: View {
    @Bindable var presentation: PinkhaHanlinChatPresentation
    @State private var composerHeight: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var followControlSide: CGFloat = 44

    public init(presentation: PinkhaHanlinChatPresentation) { self.presentation = presentation }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if presentation.hasSource {
                    Button(action: presentation.requestContextReadConsent) {
                        presentation.appearance.label(presentation.readAllowed ? PinkhaHanlinStrings.contextShared : PinkhaHanlinStrings.shareContext,
                                    .body)
                    }
                    .disabled(presentation.isStreaming || presentation.isStopping || presentation.readAllowed)
                    .accessibilityIdentifier("pinkha.hanlin.share-context")
                    .padding()
                }
                if let error = presentation.errorMessage {
                    HanlinChatErrorBanner(errorMessage: error)
                }
                if presentation.isConfigured {
                    chat
                } else {
                    PinkhaHanlinConnectionView(presentation: presentation)
                }
            }
            .navigationTitle(PinkhaHanlinStrings.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: presentation.invalidate) {
                        presentation.appearance.label(PinkhaHanlinStrings.close, .body)
                    }
                    .accessibilityIdentifier("pinkha.hanlin.close")
                }
                if presentation.hasSource {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: presentation.returnToSource) {
                            presentation.appearance.label(PinkhaHanlinStrings.returnToSource, .body)
                        }
                        .disabled(presentation.isReturningToSource)
                        .accessibilityIdentifier("pinkha.hanlin.return-to-source")
                    }
                }
            }
        }
        .hanlinFollowLatestOverlayHost(selectedConversationID: Binding(
            get: { activeConversationID }, set: { _ in }
        )) { request in
            Button(action: request.perform) {
                Image(systemName: "arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: followControlSide, height: followControlSide)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .background(.regularMaterial, in: Circle())
            .contentShape(.interaction, Circle())
            .accessibilityLabel(Text(PinkhaHanlinStrings.followLatest(
                locale: Locale(identifier: presentation.session.context.localeIdentifier))))
            .accessibilityIdentifier("pinkha.hanlin.follow-latest")
        }
        .accessibilityIdentifier("pinkha.hanlin.chat")
        .environment(\.locale, Locale(identifier: presentation.session.context.localeIdentifier))
    }

    private var activeConversationID: UUID? {
        guard presentation.isConfigured else { return nil }
        do {
            try presentation.validateInstallation(for: presentation.session)
            return presentation.session.id
        } catch { return nil }
    }

    private var chat: some View {
        HanlinChatView(shell: ShellDescriptor(id: "anytype.hanlin", title: PinkhaHanlinStrings.title)) {
            PinkhaHanlinTranscriptView(presentation: presentation,
                composerHeight: composerHeight, followControlSide: followControlSide)
                .id(presentation.session.id)
        } composer: {
            HanlinChatComposer(text: $presentation.draft, canSend: presentation.canSend,
                isStreaming: presentation.isStreaming, presentationMode: .full,
                placeholder: PinkhaHanlinStrings.prompt, isStopping: presentation.isStopping,
                stopLabel: PinkhaHanlinStrings.stop, stoppingLabel: PinkhaHanlinStrings.stopping,
                onStop: presentation.stop, onSend: presentation.send)
                .accessibilityIdentifier("pinkha.hanlin.composer")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height.isFinite, height > 0, composerHeight != height { composerHeight = height }
                }
        }
    }
}

/// The original SDK owns follow policy, coalescing, native sampling and probe
/// generations. This host binds those owners to one mounted, authorized session.
private struct PinkhaHanlinTranscriptView: View {
    let presentation: PinkhaHanlinChatPresentation
    let composerHeight: CGFloat
    let followControlSide: CGFloat
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var autoFollow = ChatAutoFollowController()
    @State private var nativeViewport = ChatScrollViewHandle()
    @State private var nativeIdleWitness = PinkhaHanlinNativeIdleWitness()
    @State private var overlayOwner = UUID()
    @State private var transcriptSize = CGSize(width: 320, height: 0)
    @State private var mounted = false
    @State private var pendingNativeIdle: PendingNativeIdle?

    private enum PendingNativeIdle {
        case observed(UUID)
        case interrupted(UUID)
    }

    private struct BottomTarget: Hashable { let sessionID: UUID }

    private var isCurrent: Bool {
        guard mounted, presentation.isConfigured else { return false }
        do {
            try presentation.validateInstallation(for: presentation.session)
            return true
        } catch { return false }
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 12) {
                        ForEach(presentation.messages) { message in
                            PinkhaHanlinMessageView(message: message, containerWidth: transcriptSize.width,
                                presentation: presentation)
                                .id(message.id)
                        }
                        ForEach(Array(presentation.receiptMessages.enumerated()), id: \.offset) { _, receipt in
                            presentation.appearance.label(receipt, .caption)
                                .foregroundStyle(presentation.appearance.secondary)
                        }
                    }
                    .padding()
                    .padding(.bottom, composerHeight)
                    // The anchor follows receipts and the actual composer
                    // clearance, so a completed tool result remains visible.
                    Color.clear.frame(height: 1)
                        .id(BottomTarget(sessionID: presentation.session.id))
                        .accessibilityHidden(true)
                }
                .chatScrollImmediateContentTouches(onOwnedScrollViewChanged: { scrollView, producerID in
                    guard nativeViewport.bind(scrollView, conversationID: presentation.session.id,
                                              producerID: producerID) else { return }
                    nativeIdleWitness.acceptedBinding(scrollView, owner: nativeViewport,
                        conversationID: presentation.session.id, producerID: producerID)
                    // These SDK callbacks are deferred; no observable state is
                    // mutated inside UIKit's attachment/layout callback.
                    scheduleNativePositionRead()
                    scheduleWhenReady(using: reader)
                })
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                if size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                   transcriptSize != size { transcriptSize = size }
            }
            .onScrollGeometryChange(for: ChatAutoFollowPosition.self) { geometry in
                ChatAutoFollowPosition(
                    layout: ChatAutoFollowLayout(contentHeight: Double(geometry.contentSize.height).rounded(),
                        viewportHeight: Double(geometry.containerSize.height).rounded(),
                        topInset: Double(geometry.contentInsets.top).rounded(),
                        bottomInset: Double(geometry.contentInsets.bottom).rounded()),
                    contentOffsetY: Double(geometry.contentOffset.y).rounded())
            } action: { previous, position in
                guard isCurrent else { return }
                autoFollow.updateLayout(position.layout)
                scheduleNativePositionRead()
                guard previous.layout != position.layout else { return }
                scheduleFollow(using: reader, measuredLayout: position.layout)
            }
            .onScrollPhaseChange { _, phase in
                guard isCurrent else { return }
                switch phase {
                case .tracking, .interacting, .decelerating:
                    pendingNativeIdle = nil
                    autoFollow.userInteractionBegan()
                case .idle:
                    pendingNativeIdle = autoFollow.state.isUserInteracting ? .observed(presentation.session.id) : nil
                    scheduleNativePositionRead()
                case .animating: break
                @unknown default: break
                }
            }
            .overlay(alignment: .bottomTrailing) { followAnchor(using: reader) }
            .onAppear {
                mounted = true
                activateViewport(using: reader)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { activateViewport(using: reader) }
                else { deactivateViewport() }
            }
            .onChange(of: presentation.isStreaming) { _, isStreaming in
                guard isCurrent, isStreaming else { return }
                autoFollow.beginRun()
                scheduleFollow(using: reader)
            }
            .onDisappear {
                mounted = false
                deactivateViewport()
            }
        }
    }

    @ViewBuilder
    private func followAnchor(using reader: ScrollViewProxy) -> some View {
        if isCurrent, autoFollow.showsScrollToBottomButton,
           transcriptSize.width >= followControlSide + 32,
           transcriptSize.height >= composerHeight + followControlSide + 16 {
            Color.clear
                .frame(width: followControlSide, height: followControlSide)
                .anchorPreference(key: HanlinFollowLatestOverlayPreferenceKey.self, value: .bounds) { bounds in
                    [HanlinFollowLatestOverlayRequest(conversationID: presentation.session.id,
                        ownerToken: overlayOwner, bounds: bounds, isTemporaryRecord: false) {
                        guard isCurrent else { return }
                        autoFollow.resumeFollowing()
                        scheduleFollow(using: reader, animated: true, force: true)
                    }]
                }
                .padding(.trailing, 16)
                .padding(.bottom, composerHeight + 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func activateViewport(using reader: ScrollViewProxy) {
        guard isCurrent else { return }
        // An interrupted gesture may lose its SwiftUI idle callback. Completion
        // still requires a fresh same-owner native idle witness after activation.
        pendingNativeIdle = autoFollow.state.isUserInteracting ? .interrupted(presentation.session.id) : nil
        nativeViewport.activate(conversationID: presentation.session.id)
        autoFollow.invalidateLayout()
        scheduleWhenReady(using: reader)
    }

    private func deactivateViewport() {
        pendingNativeIdle = nil
        _ = nativeViewport.deactivate(conversationID: presentation.session.id)
        autoFollow.invalidateLayout()
    }

    private func scheduleWhenReady(using reader: ScrollViewProxy) {
        guard isCurrent else { return }
        let sessionID = presentation.session.id
        guard nativeViewport.layout(conversationID: sessionID) != nil else { return }
        let bindingGeneration = nativeViewport.bindingGeneration
        nativeViewport.whenReady(conversationID: sessionID,
                                 expectedBindingGeneration: bindingGeneration) {
            guard isCurrent, presentation.session.id == sessionID else { return }
            if let position = nativeViewport.position(conversationID: sessionID) {
                autoFollow.updatePosition(position)
                finishPendingNativeIdle(for: sessionID)
            }
            scheduleFollow(using: reader)
        }
    }

    private func scheduleNativePositionRead() {
        guard isCurrent else { return }
        let sessionID = presentation.session.id
        guard nativeViewport.layout(conversationID: sessionID) != nil else { return }
        let bindingGeneration = nativeViewport.bindingGeneration
        nativeViewport.readPositionAfterLayout(conversationID: sessionID,
                                              expectedBindingGeneration: bindingGeneration) { position in
            guard isCurrent, presentation.session.id == sessionID,
                  let isNearBottom = position.isNearBottom else { return }
            // Keep SwiftUI's newer growth measurement while the native owner
            // supplies the current position and finishes the actual gesture.
            autoFollow.updateNearBottom(isNearBottom)
            finishPendingNativeIdle(for: sessionID)
        }
    }

    private func finishPendingNativeIdle(for sessionID: UUID) {
        guard isCurrent, presentation.session.id == sessionID,
              let completion = pendingNativeIdle else { return }
        switch completion {
        case .observed(let pendingID) where pendingID == sessionID:
            break
        case .interrupted(let pendingID) where pendingID == sessionID:
            guard let position = nativeIdleWitness.idlePosition(owner: nativeViewport, conversationID: sessionID),
                  let isNearBottom = position.isNearBottom else { return }
            autoFollow.updateNearBottom(isNearBottom)
        default:
            return
        }
        pendingNativeIdle = nil
        autoFollow.userInteractionEnded()
    }

    private func scheduleFollow(using reader: ScrollViewProxy, animated: Bool = false,
                                force: Bool = false, measuredLayout: ChatAutoFollowLayout? = nil) {
        guard isCurrent else { return }
        let sessionID = presentation.session.id
        guard let attachedLayout = nativeViewport.layout(conversationID: sessionID) else {
            autoFollow.invalidateLayout()
            return
        }
        autoFollow.updateLayout(measuredLayout ?? attachedLayout)
        let bindingGeneration = nativeViewport.bindingGeneration
        autoFollow.scheduleScroll(animated: animated, force: force) { requestedAnimation in
            guard isCurrent, presentation.session.id == sessionID,
                  nativeViewport.layout(conversationID: sessionID,
                                        expectedBindingGeneration: bindingGeneration)?.hasScrollableContent == true else { return }
            let target = BottomTarget(sessionID: sessionID)
            if requestedAnimation && !reduceMotion {
                withAnimation(.easeOut(duration: 0.18)) { reader.scrollTo(target, anchor: .bottom) }
            } else {
                reader.scrollTo(target, anchor: .bottom)
            }
            scheduleNativePositionRead()
        }
    }
}

/// Mirrors only a binding accepted by the original SDK owner. This weak,
/// non-observable witness neither schedules work nor owns follow policy.
@MainActor
private final class PinkhaHanlinNativeIdleWitness {
    private weak var scrollView: UIScrollView?
    private weak var owner: ChatScrollViewHandle?
    private var conversationID: UUID?
    private var producerID: UUID?

    func acceptedBinding(_ scrollView: UIScrollView?, owner: ChatScrollViewHandle,
                         conversationID: UUID, producerID: UUID) {
        self.scrollView = scrollView
        self.owner = owner
        self.conversationID = conversationID
        self.producerID = scrollView == nil ? nil : producerID
    }

    func idlePosition(owner: ChatScrollViewHandle, conversationID: UUID) -> ChatAutoFollowPosition? {
        guard self.owner === owner, self.conversationID == conversationID, producerID != nil,
              let scrollView, scrollView.window != nil,
              !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else { return nil }
        let generation = owner.generation
        guard let position = owner.position(conversationID: conversationID, expectedGeneration: generation),
              owner.generation == generation,
              !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else { return nil }
        return position
    }
}

private struct PinkhaHanlinConnectionView: View {
    let presentation: PinkhaHanlinChatPresentation
    @State private var endpoint = "https://api.openai.com/v1"
    @State private var model = ""
    @State private var credential = ""

    var body: some View {
        Form {
            Section {
                presentation.appearance.label(PinkhaHanlinStrings.connectionDescription, .body)
                TextField(PinkhaHanlinStrings.endpoint, text: $endpoint)
                    .accessibilityLabel(Text(PinkhaHanlinStrings.endpoint))
                    .accessibilityIdentifier("pinkha.hanlin.connection.endpoint")
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(PinkhaHanlinStrings.model, text: $model)
                    .accessibilityLabel(Text(PinkhaHanlinStrings.model))
                    .accessibilityIdentifier("pinkha.hanlin.connection.model")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(PinkhaHanlinStrings.credential, text: $credential)
                    .accessibilityLabel(Text(PinkhaHanlinStrings.credential))
                    .accessibilityIdentifier("pinkha.hanlin.connection.credential")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    presentation.configure(endpoint: endpoint, model: model, credential: credential)
                    credential = ""
                } label: {
                    presentation.appearance.label(PinkhaHanlinStrings.connect, .body)
                }
                .accessibilityIdentifier("pinkha.hanlin.connect")
            }
            Section {
                presentation.appearance.label(PinkhaHanlinStrings.sessionPrivacy, .caption)
            }
        }
        .onDisappear { credential = "" }
    }
}

@MainActor
public final class PinkhaHanlinChatController: UIHostingController<PinkhaHanlinChatView>, UIAdaptivePresentationControllerDelegate {
    public let presentation: PinkhaHanlinChatPresentation

    public init(presentation: PinkhaHanlinChatPresentation) {
        self.presentation = presentation
        super.init(rootView: PinkhaHanlinChatView(presentation: presentation))
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { return nil }

    public func revoke() { presentation.invalidate() }
    public func drain() async { await presentation.revokeAndDrain() }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
        presentation.didMount(self)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent || presentingViewController == nil {
            presentation.ownerWillDisappear()
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            presentation.observedInvalidation("presentationRemoved")
            presentation.invalidate()
        }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presentation.observedInvalidation("interactivePresentationDismissal")
        presentation.invalidate()
    }
}

#endif
