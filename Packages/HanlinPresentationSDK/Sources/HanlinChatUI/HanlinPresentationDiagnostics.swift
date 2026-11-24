import Foundation

/// The host may connect its existing diagnostic sink without making the shared
/// presentation components depend on a global logger or an application account.
/// Callbacks run on the same UI actor as the originating component.
public typealias HanlinPresentationTraceHandler = @MainActor @Sendable (String, [String: Any]) -> Void
