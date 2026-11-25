#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import Observation

public enum HanlinSheetAppearance: String, CaseIterable, Hashable, Sendable {
    case system, regularMaterial, ultraThinMaterial, regularGlass, clearGlass
}

public enum HanlinSheetPlacement: String, CaseIterable, Hashable, Sendable {
    case automatic, leading, center, trailing

    var systemValue: PresentationPlacement {
        switch self {
        case .automatic: .automatic
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

public struct HanlinChatPresentationConfiguration {
    public var policy: HanlinChatPresentationPolicy
    public var sheetAppearance: HanlinSheetAppearance
    public var placement: HanlinSheetPlacement
    public var detents: Set<PresentationDetent>
    public var initialDetent: PresentationDetent
    public var backgroundInteraction: PresentationBackgroundInteraction
    public var inspectorMinimumWidth: CGFloat
    public var inspectorIdealWidth: CGFloat
    public var inspectorMaximumWidth: CGFloat

    public init(modes: Set<HanlinChatPresentationMode> = [.sheet, .inspector],
                initialMode: HanlinChatPresentationMode = .sheet,
                sheetAppearance: HanlinSheetAppearance = .clearGlass,
                placement: HanlinSheetPlacement = .leading,
                detents: Set<PresentationDetent> = [.height(240), .medium, .large],
                initialDetent: PresentationDetent = .medium,
                backgroundInteraction: PresentationBackgroundInteraction = .enabled(upThrough: .medium),
                inspectorMinimumWidth: CGFloat = 300,
                inspectorIdealWidth: CGFloat = 420,
                inspectorMaximumWidth: CGFloat = 650) {
        self.policy = .init(modes: modes, initialMode: initialMode)
        self.sheetAppearance = sheetAppearance
        self.placement = placement
        let valid = detents.isEmpty ? Set([PresentationDetent.medium, .large]) : detents
        // Always admit the requested initial detent so the selection is legal.
        self.detents = valid.union([initialDetent])
        self.initialDetent = initialDetent
        self.backgroundInteraction = backgroundInteraction
        let low = inspectorMinimumWidth.isFinite ? max(220, inspectorMinimumWidth) : 300
        let high = inspectorMaximumWidth.isFinite ? max(low, inspectorMaximumWidth) : max(low, 650)
        let ideal = inspectorIdealWidth.isFinite ? inspectorIdealWidth : 420
        self.inspectorMinimumWidth = low
        self.inspectorMaximumWidth = high
        self.inspectorIdealWidth = min(high, max(low, ideal))
    }
}

/// Host-supplied text permits localization without a second localization store.
public struct HanlinLauncherLabels: Sendable {
    public var title: String
    public var ask: String
    public var placeholder: String
    public var send: String
    public var close: String
    public var sheet: String
    public var inspector: String
    public init(title: String = "Hanlin", ask: String = "Ask Hanlin",
                placeholder: String = "Ask anything…", send: String = "Send",
                close: String = "Close", sheet: String = "Open in sheet",
                inspector: String = "Open in inspector") {
        self.title = title; self.ask = ask; self.placeholder = placeholder
        self.send = send; self.close = close; self.sheet = sheet; self.inspector = inspector
    }
}

/// A single controller per host workspace. Keep the actual session, composer
/// draft and streaming task in the host, not inside a presented view.
@MainActor @Observable
public final class HanlinChatPresentationController {
    public private(set) var configuration: HanlinChatPresentationConfiguration
    public private(set) var state: HanlinChatPresentationState
    public var detent: PresentationDetent

    public init(configuration: HanlinChatPresentationConfiguration = .init()) {
        self.configuration = configuration
        self.state = .init(policy: configuration.policy)
        self.detent = configuration.initialDetent
    }

    public var mode: HanlinChatPresentationMode? { state.mode }
    public var isPresented: Bool { state.phase != .closed }
    public var isTransitioning: Bool { state.isTransitioning }

    @discardableResult
    public func configure(_ configuration: HanlinChatPresentationConfiguration) -> Bool {
        guard state.configure(configuration.policy) else { return false }
        self.configuration = configuration
        detent = configuration.initialDetent
        return true
    }

    public func present(_ mode: HanlinChatPresentationMode? = nil) { state.open(mode) }

    public func toggle() {
        guard !isTransitioning else { return }
        if isPresented { dismiss() } else { present() }
    }

    public func switchTo(_ mode: HanlinChatPresentationMode) {
        guard !isTransitioning, configuration.policy.modes.contains(mode), self.mode != mode else { return }
        if state.mode == .inspector {
            withAnimation(.default, completionCriteria: .removed) {
                state.request(mode)
            } completion: { [weak self] in
                // The inspector's native disappearance also completes the
                // transition. The state machine rejects duplicate completions.
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.finish(.inspector)
                }
            }
        } else {
            state.request(mode)
        }
    }

    public func dismiss() {
        if state.mode == .inspector {
            withAnimation(.default, completionCriteria: .removed) {
                state.close()
            } completion: { [weak self] in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.finish(.inspector)
                }
            }
        } else {
            state.close()
        }
    }

    fileprivate func binding(_ mode: HanlinChatPresentationMode) -> Binding<Bool> {
        Binding(get: { self.state.isShowing(mode) }, set: { visible in
            if !visible { self.state.systemDismissed(mode) }
        })
    }

    fileprivate func finish(_ mode: HanlinChatPresentationMode) {
        state.finishDismissal(mode)
    }
}

/// Opt-in native zoom. Host must provide one stable namespace/source ID for
/// its launcher and sheet. Off by default to preserve the system placement.
public struct HanlinLauncherTransition {
    public let namespace: Namespace.ID
    public let sourceID: String
    public init(namespace: Namespace.ID, sourceID: String = "hanlin-launcher") {
        self.namespace = namespace; self.sourceID = sourceID
    }
}

@MainActor
private struct HanlinPresentationModifier<Chat: View>: ViewModifier {
    let controller: HanlinChatPresentationController
    let labels: HanlinLauncherLabels
    let transition: HanlinLauncherTransition?
    let chat: (HanlinChatPresentationMode) -> Chat

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: controller.binding(.sheet),
                   onDismiss: { controller.finish(.sheet) }) {
                sheet
            }
            .inspector(isPresented: controller.binding(.inspector)) {
                panel(.inspector)
                    .inspectorColumnWidth(min: controller.configuration.inspectorMinimumWidth,
                                          ideal: controller.configuration.inspectorIdealWidth,
                                          max: controller.configuration.inspectorMaximumWidth)
                    .onDisappear {
                        Task { @MainActor in
                            await Task.yield()
                            controller.finish(.inspector)
                        }
                    }
            }
    }

    @ViewBuilder
    private var sheet: some View {
        let config = controller.configuration
        let base = panel(.sheet)
            .presentationDetents(config.detents, selection: Binding(
                get: { controller.detent }, set: { controller.detent = $0 }))
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(config.backgroundInteraction)
            .presentationPlacement(config.placement.systemValue)
        let decorated = base.modifier(HanlinSheetSurface(appearance: config.sheetAppearance))
        if let transition {
            decorated.navigationTransition(.zoom(sourceID: transition.sourceID, in: transition.namespace))
        } else {
            decorated
        }
    }

    private func panel(_ mode: HanlinChatPresentationMode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(labels.title, systemImage: "sparkles")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let alternative = controller.configuration.policy.alternative(to: mode) {
                    Button {
                        controller.switchTo(alternative)
                    } label: {
                        Image(systemName: alternative == .inspector
                              ? "sidebar.right" : "rectangle.bottomthird.inset.filled")
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(alternative == .inspector ? labels.inspector : labels.sheet)
                    .accessibilityIdentifier("hanlin-presentation-switch")
                }
                Button(action: controller.dismiss) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(labels.close)
                .accessibilityIdentifier("hanlin-presentation-close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            chat(mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(mode == .sheet ? "hanlin-native-sheet" : "hanlin-native-inspector")
    }
}

private struct HanlinSheetSurface: ViewModifier {
    let appearance: HanlinSheetAppearance
    @ViewBuilder func body(content: Content) -> some View {
        switch appearance {
        case .system: content
        case .regularMaterial: content.presentationBackground(.regularMaterial)
        case .ultraThinMaterial: content.presentationBackground(.ultraThinMaterial)
        case .regularGlass:
            content.presentationBackground {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30))
                    .ignoresSafeArea()
            }
        case .clearGlass:
            content.presentationBackground {
                Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 30))
                    .ignoresSafeArea()
            }
        }
    }
}

public extension View {
    /// The SDK owns only the native presentation. The same host-owned session
    /// can be rendered in either mode; never create a session in this closure.
    @MainActor
    func hanlinChatPresentation<Chat: View>(
        controller: HanlinChatPresentationController,
        labels: HanlinLauncherLabels = .init(),
        transition: HanlinLauncherTransition? = nil,
        @ViewBuilder chat: @escaping (HanlinChatPresentationMode) -> Chat
    ) -> some View {
        modifier(HanlinPresentationModifier(controller: controller, labels: labels,
                                            transition: transition, chat: chat))
    }
}
#endif

