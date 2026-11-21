#if canImport(SwiftUI)
//
//  ChatShimmerEffect.swift
//  AI_HLY
//
//  Modern shimmering light sweep effect for agent thinking and tool execution states.
//

import SwiftUI

struct ChatShimmerModifier: ViewModifier {
    let isActive: Bool
    let colors: [Color]?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.chatMotion) private var motion

    init(isActive: Bool = true, colors: [Color]? = nil) {
        self.isActive = isActive
        self.colors = colors
    }

    func body(content: Content) -> some View {
        if !isActive || reduceMotion || scenePhase != .active || !motion.showsShimmer {
            content
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                        let width = geo.size.width
                        let shimmerColor = Color.blue
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let phase = time.truncatingRemainder(dividingBy: motion.shimmerDuration) / motion.shimmerDuration * 2 - 1

                        LinearGradient(
                            colors: colors ?? [shimmerColor.opacity(0), shimmerColor.opacity(0.35),
                                shimmerColor.opacity(0.85), shimmerColor.opacity(0.35), shimmerColor.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(width * 1.5, 120))
                        .offset(x: phase * (width + 120) - 60)
                        }
                    }
                    .mask(content)
                }
        }
    }
}

public extension View {
    /// Applies a glowing shimmer sweep animation passing across the view.
    func chatShimmer(isActive: Bool = true, colors: [Color]? = nil) -> some View {
        modifier(ChatShimmerModifier(isActive: isActive, colors: colors))
    }
}

#endif
