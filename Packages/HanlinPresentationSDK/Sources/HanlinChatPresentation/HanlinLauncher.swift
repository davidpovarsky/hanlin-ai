#if os(iOS) && canImport(SwiftUI)
import SwiftUI

/// Placement is deliberately host-owned: add the toolbar variant to a native
/// ToolbarItem, or the floating/quick variants to an overlay or safe-area inset.
@MainActor
public struct HanlinLauncher: View {
    public let style: HanlinLauncherStyle
    public let controller: HanlinChatPresentationController
    public let labels: HanlinLauncherLabels
    public let transition: HanlinLauncherTransition?
    @Binding private var draft: String
    private let onQuickSubmit: (String) -> Void
    @State private var quickExpanded = false
    @FocusState private var quickFocused: Bool

    public init(style: HanlinLauncherStyle,
                controller: HanlinChatPresentationController,
                draft: Binding<String> = .constant(""),
                labels: HanlinLauncherLabels = .init(),
                transition: HanlinLauncherTransition? = nil,
                onQuickSubmit: @escaping (String) -> Void = { _ in }) {
        self.style = style; self.controller = controller
        self._draft = draft; self.labels = labels; self.transition = transition
        self.onQuickSubmit = onQuickSubmit
    }

    public var body: some View {
        Group {
            // Remove entry controls from layout and accessibility while either
            // native surface owns the conversation, including handoffs.
            if controller.showsLauncher {
                if let transition {
                    launcher.matchedTransitionSource(id: transition.sourceID, in: transition.namespace)
                } else {
                    launcher
                }
            }
        }
        .onChange(of: controller.isPresented) { _, open in
            if open {
                quickFocused = false
                quickExpanded = false
            }
        }
    }

    @ViewBuilder private var launcher: some View {
        switch style {
        case .toolbarCapsule:
            Button { controller.present() } label: {
                Label(labels.title, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            // A native ToolbarItem already supplies its own Liquid Glass.
            // Do not nest a GlassButtonStyle inside the system toolbar glass.
            .buttonStyle(.automatic)
            .accessibilityLabel(labels.ask)
            .accessibilityIdentifier("hanlin-launcher-toolbar")
        case .floatingCapsule:
            Button { controller.present() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title3.weight(.semibold))
                    Text(labels.ask)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityIdentifier("hanlin-launcher-floating")
        case .quickComposer:
            GlassEffectContainer(spacing: 10) {
                if quickExpanded {
                    quickField
                } else {
                    Button {
                        quickExpanded = true
                        quickFocused = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(labels.ask)
                    .accessibilityIdentifier("hanlin-launcher-quick")
                }
            }
        }
    }

    private var quickField: some View {
        HStack(spacing: 8) {
            Button {
                quickFocused = false
                controller.present()
            } label: {
                Image(systemName: "sparkles")
                    .frame(minWidth: 40, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(labels.ask)
            TextField(labels.placeholder, text: $draft)
                .font(.body)
                .focused($quickFocused)
                .submitLabel(.send)
                .onSubmit(submit)
                .accessibilityIdentifier("hanlin-quick-field")
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(labels.send)
            .accessibilityIdentifier("hanlin-quick-send")
            Button {
                quickFocused = false
                quickExpanded = false
            } label: {
                Image(systemName: "xmark")
                    .frame(minWidth: 34, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(labels.close)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: Capsule())
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, controller.showsLauncher else { return }
        quickFocused = false
        controller.present()
        onQuickSubmit(text)
        quickExpanded = false
    }
}
#endif
