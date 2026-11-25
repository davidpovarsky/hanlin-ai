import Foundation

/// The active Expo/NativeScript engines depend on this session-bound capability,
/// never on the AI target's model database, credentials, or a second JavaScript SDK.
public protocol HanlinMiniAppAssistantService: Sendable {
    func invoke(operation: String, payloadJSON: String) async throws -> String
    /// Revoke admission synchronously; the implementation then drains pending work.
    func invalidate()
}

public typealias HanlinMiniAppAssistantServiceFactory =
    @Sendable (HanlinHostCallContext) -> (any HanlinMiniAppAssistantService)?
