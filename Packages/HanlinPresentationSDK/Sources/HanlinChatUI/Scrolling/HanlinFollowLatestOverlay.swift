#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// A transient presentation request. The current transcript retains its scroll
/// action; the host resolves only its original control's bounds.
public struct HanlinFollowLatestOverlayRequest {
    public let conversationID: UUID
    public let ownerToken: UUID
    public let bounds: Anchor<CGRect>
    public let isTemporaryRecord: Bool
    private let action: @MainActor () -> Void

    public init(conversationID: UUID, ownerToken: UUID, bounds: Anchor<CGRect>,
                isTemporaryRecord: Bool, action: @escaping @MainActor () -> Void) {
        self.conversationID = conversationID
        self.ownerToken = ownerToken
        self.bounds = bounds
        self.isTemporaryRecord = isTemporaryRecord
        self.action = action
    }

    @MainActor public func perform() { action() }
}

public struct HanlinFollowLatestOverlayPreferenceKey: PreferenceKey {
    public static var defaultValue: [HanlinFollowLatestOverlayRequest] { [] }

    public static func reduce(value: inout [HanlinFollowLatestOverlayRequest],
                              nextValue: () -> [HanlinFollowLatestOverlayRequest]) {
        value.append(contentsOf: nextValue())
    }
}

private struct FollowLatestExternalHostKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var hanlinFollowLatestHostedExternally: Bool {
        get { self[FollowLatestExternalHostKey.self] }
        set { self[FollowLatestExternalHostKey.self] = newValue }
    }
}

/// Give only the resolved control region its own native hosting boundary.
/// SwiftUI owns the controller view's bounds; the surrounding overlay stays empty.
@MainActor
private struct FollowLatestHostedControl<Control: View>: UIViewControllerRepresentable {
    let control: Control
    @Environment(\.self) private var environment

    typealias UIViewControllerType = UIHostingController<FollowLatestHostedControlRoot<Control>>

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let controller = UIHostingController(rootView: rootView)
        // The transcript's anchor already accounts for safe areas and the keyboard.
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.isOpaque = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewControllerType, context: Context) {
        // Replace the value so the original Button receives the current guarded action.
        controller.rootView = rootView
    }

    static func dismantleUIViewController(_ controller: UIViewControllerType, coordinator: ()) {
        // Release both the action and the captured parent environment.
        controller.rootView = FollowLatestHostedControlRoot(
            control: nil, environment: EnvironmentValues()
        )
    }

    private var rootView: FollowLatestHostedControlRoot<Control> {
        FollowLatestHostedControlRoot(control: control, environment: environment)
    }
}

@MainActor
private struct FollowLatestHostedControlRoot<Control: View>: View {
    var control: Control?
    let environment: EnvironmentValues

    var body: some View {
        Group {
            if let control {
                control
            }
        }
        .environment(\.self, environment)
    }
}

@MainActor
private struct FollowLatestOverlayHost<Control: View>: ViewModifier {
    let selectedConversationID: Binding<UUID?>
    let control: @MainActor (HanlinFollowLatestOverlayRequest) -> Control

    func body(content: Content) -> some View {
        content
            .environment(\.hanlinFollowLatestHostedExternally, true)
            .overlayPreferenceValue(HanlinFollowLatestOverlayPreferenceKey.self) { requests in
                GeometryReader { geometry in
                    let request = currentRequest(in: requests)
                    Group {
                        if let request {
                            let frame = geometry[request.bounds]
                            if frame.minX.isFinite, frame.minY.isFinite,
                               frame.width.isFinite, frame.height.isFinite,
                               frame.width > 0, frame.height > 0 {
                                FollowLatestHostedControl(control: control(guarded(request)))
                                    .frame(width: frame.width, height: frame.height)
                                    .id(request.ownerToken)
                                    .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7),
                               value: request?.ownerToken)
                }
            }
    }

    private func currentRequest(in requests: [HanlinFollowLatestOverlayRequest])
        -> HanlinFollowLatestOverlayRequest? {
        guard let selected = selectedConversationID.wrappedValue else { return nil }
        let matching = requests.filter { $0.conversationID == selected }
        // A navigation transition must never mount two copies of the action.
        return matching.count == 1 ? matching[0] : nil
    }

    private func guarded(_ request: HanlinFollowLatestOverlayRequest)
        -> HanlinFollowLatestOverlayRequest {
        HanlinFollowLatestOverlayRequest(
            conversationID: request.conversationID, ownerToken: request.ownerToken,
            bounds: request.bounds, isTemporaryRecord: request.isTemporaryRecord
        ) {
            // Read the live selection at activation, not the preceding render.
            guard selectedConversationID.wrappedValue == request.conversationID else { return }
            request.perform()
        }
    }
}

public extension View {
    /// Place the one follow-latest control outside a navigation container while
    /// retaining its transcript-relative anchor, style and current scroll action.
    /// Preferences are consumed directly; no copied geometry or stored proxy is
    /// kept by this host. Empty overlay space has no hit-testing surface.
    @MainActor
    func hanlinFollowLatestOverlayHost<Control: View>(
        selectedConversationID: Binding<UUID?>,
        @ViewBuilder control: @escaping @MainActor (HanlinFollowLatestOverlayRequest) -> Control
    ) -> some View {
        modifier(FollowLatestOverlayHost(selectedConversationID: selectedConversationID,
                                         control: control))
    }
}
#endif
