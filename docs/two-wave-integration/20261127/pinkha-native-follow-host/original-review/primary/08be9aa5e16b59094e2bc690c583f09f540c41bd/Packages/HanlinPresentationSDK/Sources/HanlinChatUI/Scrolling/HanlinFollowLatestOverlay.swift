#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

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
                                control(guarded(request))
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

/// Export only the selected wide conversation. The scene host owns placement;
/// this source keeps the live selection guard next to the conversation owner.
@MainActor
private struct FollowLatestOverlaySource: ViewModifier {
    let selectedConversationID: Binding<UUID?>
    let onActionAttempt: (@MainActor (HanlinFollowLatestOverlayRequest) -> Void)?

    func body(content: Content) -> some View {
        content
            .environment(\.hanlinFollowLatestHostedExternally, true)
            .transformPreference(HanlinFollowLatestOverlayPreferenceKey.self) { requests in
                guard let selected = selectedConversationID.wrappedValue else {
                    requests.removeAll()
                    return
                }
                requests = requests.filter { $0.conversationID == selected }.map { request in
                    HanlinFollowLatestOverlayRequest(
                        conversationID: request.conversationID, ownerToken: request.ownerToken,
                        bounds: request.bounds, isTemporaryRecord: request.isTemporaryRecord
                    ) {
                        onActionAttempt?(request)
                        guard selectedConversationID.wrappedValue == request.conversationID else { return }
                        request.perform()
                    }
                }
            }
    }
}

/// Consume exported anchors above the native tab container. This host does not
/// change descendant environments, so compact conversations keep their local control.
@MainActor
private struct FollowLatestSceneOverlayHost<Control: View>: ViewModifier {
    let isEnabled: Binding<Bool>
    let control: @MainActor (HanlinFollowLatestOverlayRequest) -> Control

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(HanlinFollowLatestOverlayPreferenceKey.self) { requests in
                GeometryReader { geometry in
                    let request = currentRequest(in: requests)
                    Group {
                        if let request {
                            let frame = geometry[request.bounds]
                            if frame.minX.isFinite, frame.minY.isFinite,
                               frame.width.isFinite, frame.height.isFinite,
                               frame.width > 0, frame.height > 0 {
                                control(guarded(request))
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
        guard isEnabled.wrappedValue, requests.count == 1 else { return nil }
        return requests[0]
    }

    private func guarded(_ request: HanlinFollowLatestOverlayRequest)
        -> HanlinFollowLatestOverlayRequest {
        HanlinFollowLatestOverlayRequest(
            conversationID: request.conversationID, ownerToken: request.ownerToken,
            bounds: request.bounds, isTemporaryRecord: request.isTemporaryRecord
        ) {
            // Re-read the current tab before invoking the source's live selection guard.
            guard isEnabled.wrappedValue else { return }
            request.perform()
        }
    }
}

public extension View {
    /// Export a wide conversation's anchor and action to an enclosing scene host.
    /// The optional callback observes an action attempt before the live selection guard.
    @MainActor
    func hanlinFollowLatestOverlaySource(
        selectedConversationID: Binding<UUID?>,
        onActionAttempt: (@MainActor (HanlinFollowLatestOverlayRequest) -> Void)? = nil
    ) -> some View {
        modifier(FollowLatestOverlaySource(selectedConversationID: selectedConversationID,
                                           onActionAttempt: onActionAttempt))
    }

    /// Mount one exported control outside a native tab container. Only sources
    /// explicitly opting into external hosting publish requests; no geometry is cached.
    @MainActor
    func hanlinFollowLatestSceneOverlayHost<Control: View>(
        isEnabled: Binding<Bool>,
        @ViewBuilder control: @escaping @MainActor (HanlinFollowLatestOverlayRequest) -> Control
    ) -> some View {
        modifier(FollowLatestSceneOverlayHost(isEnabled: isEnabled, control: control))
    }

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
