import Foundation
import SwiftUI

private struct HanlinAIReceivingWindowIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// Identity of this WindowGroup content instance, not a ChatView Session/scene identity.
    var hanlinAIReceivingWindowID: UUID? {
        get { self[HanlinAIReceivingWindowIDKey.self] }
        set { self[HanlinAIReceivingWindowIDKey.self] = newValue }
    }
}

/// State belongs inside the scene's view hierarchy so every actual window gets its own token.
/// The initial UUID has no IO/authority; SwiftUI retains the State for that content's lifetime.
@MainActor
struct HanlinAIReceivingWindowRoot<Content: View>: View {
    @State private var receivingWindowID = UUID()
    private let content: @MainActor (UUID) -> Content

    init(@ViewBuilder content: @escaping @MainActor (UUID) -> Content) { self.content = content }

    var body: some View {
        content(receivingWindowID)
            .environment(\.hanlinAIReceivingWindowID, receivingWindowID)
    }
}
