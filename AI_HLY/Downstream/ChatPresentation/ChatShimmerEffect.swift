//
//  ChatShimmerEffect.swift
//  AI_HLY
//
//  Modern shimmering light sweep effect for agent thinking and tool execution states.
//

import SwiftUI

struct ChatShimmerModifier: ViewModifier {
    let isActive: Bool
    let animationDuration: Double

    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(isActive: Bool = true, animationDuration: Double = 1.8) {
        self.isActive = isActive
        self.animationDuration = animationDuration
    }

    func body(content: Content) -> some View {
        if !isActive || reduceMotion {
            content
        } else {
            content
                .overlay {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let shimmerColor = colorScheme == .dark ? Color.white : Color.primary

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
                    .mask(content)
                }
                .onAppear {
                    phase = -1.0
                    withAnimation(
                        .linear(duration: animationDuration)
                            .repeatForever(autoreverses: false)
                    ) {
                        phase = 1.0
                    }
                }
        }
    }
}

extension View {
    /// Applies a glowing shimmer sweep animation passing across the view.
    func chatShimmer(isActive: Bool = true, animationDuration: Double = 1.8) -> some View {
        modifier(ChatShimmerModifier(isActive: isActive, animationDuration: animationDuration))
    }
}
