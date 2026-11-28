import Foundation

/// A preview is a viewport, never the intrinsic height of the entire reply.
public struct HanlinMessagePreviewMetrics: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public static func fitting(preferredWidth: Double, windowWidth: Double, windowHeight: Double) -> Self? {
        guard windowWidth.isFinite, windowHeight.isFinite, windowWidth > 48, windowHeight > 80 else { return nil }
        let requested = preferredWidth.isFinite && preferredWidth > 0 ? preferredWidth : 480
        return Self(width: min(480, max(260, requested), windowWidth - 48), height: min(680, windowHeight - 80))
    }
}
