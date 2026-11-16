//
//  ChatShimmerEffect.swift
//  AI_HLY
//
//  Modern shimmering light sweep effect for agent thinking and tool execution states.
//

import SwiftUI

struct ChatShimmerModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.chatMotion) private var motion

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    func body(content: Content) -> some View {
        if !isActive || reduceMotion || scenePhase != .active || !motion.showsShimmer {
            content
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        TimelineView(.animation) { timeline in
                        let width = geo.size.width
                        let shimmerColor = Color.blue
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let phase = time.truncatingRemainder(dividingBy: motion.shimmerDuration) / motion.shimmerDuration * 2 - 1

                        LinearGradient(
                            stops: [
                                .init(color: shimmerColor.opacity(0.0), location: 0.0),
                                .init(color: shimmerColor.opacity(0.35), location: 0.35),
                                .init(color: shimmerColor.opacity(0.85), location: 0.5),
                                .init(color: shimmerColor.opacity(0.35), location: 0.65),
                                .init(color: shimmerColor.opacity(0.0), location: 1.0)
                            ],
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

extension View {
    /// Applies a glowing shimmer sweep animation passing across the view.
    func chatShimmer(isActive: Bool = true) -> some View {
        modifier(ChatShimmerModifier(isActive: isActive))
    }
}
