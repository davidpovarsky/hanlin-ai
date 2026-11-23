import HanlinLocalization
#if canImport(SwiftUI)
import SwiftUI

private struct ChatMotionKey: EnvironmentKey {
    static let defaultValue = ChatMotionConfiguration.forPreset(.relaxed)
}

public extension EnvironmentValues {
    var chatMotion: ChatMotionConfiguration {
        get { self[ChatMotionKey.self] }
        set { self[ChatMotionKey.self] = newValue }
    }
}

public extension ChatMotionConfiguration {
    private func animation(duration: Double) -> Animation? {
        guard duration > 0 else { return nil }
        switch curve {
        case .easeInOut: return .easeInOut(duration: duration)
        case .easeOut: return .easeOut(duration: duration)
        }
    }
    func disclosureAnimation(expanding: Bool) -> Animation? {
        animation(duration: expanding ? openingDuration : closingDuration)
    }
    var updateAnimation: Animation? { animation(duration: updateDuration) }
    var resultAnimation: Animation? { animation(duration: resultDuration) }
    var resultTransition: AnyTransition {
        isAnimated ? .scale(scale: resultScale).combined(with: .opacity).animation(resultAnimation) : .identity
    }
}

private struct ChatMotionPreferences: ViewModifier {
    @AppStorage(ChatMotionPreset.storageKey) private var storedID = ChatMotionPreset.relaxed.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.chatMotion, .forPreset(.fromStoredID(storedID), reduceMotion: reduceMotion))
            .onAppear { normalize() }
            .onChange(of: storedID) { _, _ in normalize() }
    }

    private func normalize() {
        let validID = ChatMotionPreset.fromStoredID(storedID).rawValue
        if storedID != validID { storedID = validID }
    }
}

public extension View {
    func chatMotionPreferences() -> some View { modifier(ChatMotionPreferences()) }
}

/// The sole user-facing control, embedded in the existing General Settings.
public struct ChatMotionPresetPicker: View {
    public init() {}
    @AppStorage(ChatMotionPreset.storageKey) private var storedID = ChatMotionPreset.relaxed.rawValue

    public var body: some View {
        Picker(selection: Binding(
            get: { ChatMotionPreset.fromStoredID(storedID) },
            set: { storedID = $0.rawValue }
        )) {
            Text("Smooth and relaxed", bundle: HanlinLocalization.bundle).tag(ChatMotionPreset.relaxed)
            Text("Height reveal", bundle: HanlinLocalization.bundle).tag(ChatMotionPreset.heightReveal)
            Text("Gentle squeeze", bundle: HanlinLocalization.bundle).tag(ChatMotionPreset.gentleSqueeze)
            Text("Quiet fade", bundle: HanlinLocalization.bundle).tag(ChatMotionPreset.quietFade)
            Text("No animations", bundle: HanlinLocalization.bundle).tag(ChatMotionPreset.none)
        } label: {
            Label(hanlin: "Chat animations", systemImage: "sparkles")
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("hanlin-chat-motion-preset")
        .onAppear {
            storedID = ChatMotionPreset.fromStoredID(storedID).rawValue
        }
    }
}

#endif
