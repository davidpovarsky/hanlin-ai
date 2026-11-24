#if canImport(SwiftUI)
import SwiftUI

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

/// The V17 title treatment, shared by reasoning, operational and tool titles.
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
            .foregroundStyle(active ? (appearance.activeTitle ?? Color(red: 0.24, green: 0.43, blue: 0.68)) : baseColor)
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
                            // V17 SweepAcrossLetters: the light crosses only the
                            // letters; no large moving background or frame state.
                            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
                            let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
                            let beamWidth = max(CGFloat(32), width * 0.54)
                            let duration = motion.shimmerDuration
                            let seconds = max(0, (stoppedAt ?? timeline.date)
                                .timeIntervalSince(startedAt ?? Date(timeIntervalSinceReferenceDate: 0)))
                            let progress = seconds.truncatingRemainder(dividingBy: duration) / duration
                            let position = CGFloat(progress) * (width + beamWidth) - beamWidth
                            LinearGradient(
                                colors: colors ?? appearance.shimmerColors ?? [
                                    .clear,
                                    Color(red: 0.32, green: 0.65, blue: 0.98).opacity(0.32),
                                    Color(red: 0.63, green: 0.83, blue: 1.00),
                                    .white.opacity(0.96),
                                    Color(red: 0.36, green: 0.66, blue: 0.97).opacity(0.4),
                                    .clear
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
