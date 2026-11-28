#if canImport(SwiftUI)
import SwiftUI
import HanlinLocalization

private struct HanlinActivityBranchVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// Closing a hierarchy pauses its mounted descendants during height reveal.
    var hanlinActivityBranchVisible: Bool {
        get { self[HanlinActivityBranchVisibilityKey.self] }
        set { self[HanlinActivityBranchVisibilityKey.self] = newValue }
    }
}

/// The original Hanlin blue sweep, shared by reasoning and active tool titles.
public struct HanlinActivityTitle: View {
    private let title: String
    private let font: Font
    private let baseColor: Color
    private let active: Bool
    private let startedAt: Date?
    private let stoppedAt: Date?
    @Environment(\.hanlinChatAppearance) private var appearance

    public init(_ title: String, font: Font, baseColor: Color = .secondary, isActive: Bool,
                startedAt: Date? = nil, stoppedAt: Date? = nil) {
        self.title = title
        self.font = font
        self.baseColor = baseColor
        self.active = isActive
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
    }

    public var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(active ? (appearance.activeTitle ?? .gray) : baseColor)
            .chatShimmer(isActive: active, startedAt: startedAt, stoppedAt: stoppedAt)
    }
}

struct ChatShimmerModifier: ViewModifier {
    let isActive: Bool
    let colors: [Color]?
    let startedAt: Date?
    let stoppedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.chatMotion) private var motion
    @Environment(\.hanlinActivityBranchVisible) private var branchIsVisible
    @Environment(\.hanlinChatAppearance) private var appearance

    init(isActive: Bool = true, colors: [Color]? = nil,
         startedAt: Date? = nil, stoppedAt: Date? = nil) {
        self.isActive = isActive
        self.colors = colors
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if isActive && branchIsVisible && !reduceMotion && !voiceOver
                    && scenePhase == .active && motion.showsShimmer {
                    GeometryReader { geometry in
                        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: stoppedAt != nil)) { timeline in
                            // Preserve the original full-width blue sweep over
                            // gray letters, with the shared bounded motion clock.
                            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
                            let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
                            let beamWidth = width
                            let duration = motion.shimmerDuration
                            let seconds = max(0, (stoppedAt ?? timeline.date)
                                .timeIntervalSince(startedAt ?? Date(timeIntervalSinceReferenceDate: 0)))
                            let progress = seconds.truncatingRemainder(dividingBy: duration) / duration
                            let position = CGFloat(progress) * (width + beamWidth) - beamWidth
                            LinearGradient(
                                colors: colors ?? appearance.shimmerColors ?? [
                                    Color.hanlinHLBluefont.opacity(0.0),
                                    Color.hanlinHLBluefont.opacity(0.2),
                                    Color.hanlinHLBluefont.opacity(0.6),
                                    Color.hanlinHLBluefont.opacity(1.0),
                                    Color.hanlinHLBluefont.opacity(0.6),
                                    Color.hanlinHLBluefont.opacity(0.2),
                                    Color.hanlinHLBluefont.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: beamWidth, height: height)
                            .offset(x: position)
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

public extension View {
    func chatShimmer(isActive: Bool = true, colors: [Color]? = nil,
                     startedAt: Date? = nil, stoppedAt: Date? = nil) -> some View {
        modifier(ChatShimmerModifier(isActive: isActive, colors: colors,
            startedAt: startedAt, stoppedAt: stoppedAt))
    }
}
#endif
