#if canImport(SwiftUI)
import SwiftUI

/// A view of real Host activity. The host selects a family only from its trusted
/// tool descriptor. Motion is decorative and never represents fabricated progress.
public struct HanlinToolActivityHeader: View {
    public enum Family: String, Sendable { case generic, webSearch, fileOperation, codeExecution, command, sourceSearch, imageGeneration, map }
    private let title: String
    private let status: String
    private let symbol: String
    private let family: Family
    private let active: Bool
    @Environment(\.chatMotion) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.layoutDirection) private var direction
    @State private var lastPhase: Double = 0
    @State private var frozenPhase: Double = 0
    @State private var hasStarted = false

    public init(title: String, status: String, symbol: String, family: Family = .generic, isActive: Bool) {
        self.title = title; self.status = status; self.symbol = symbol
        self.family = family; self.active = isActive
    }
    private var animates: Bool { active && motion.isAnimated && !reduceMotion && !voiceOver && scenePhase == .active }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.subheadline).accessibilityHidden(true)
                Text(title).font(.subheadline).chatShimmer(isActive: animates)
                Spacer(minLength: 8)
                Text(status).font(.caption2).foregroundStyle(.secondary)
                    .contentTransition(.opacity).animation(motion.updateAnimation, value: status)
            }
            if hasStarted && motion.isAnimated && !reduceMotion && !voiceOver {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                    let moving = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                    let phase = animates ? moving : frozenPhase
                    GeometryReader { geometry in
                        let x = (direction == .rightToLeft ? 1 - phase : phase) * max(0, geometry.size.width - 14)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.blue.opacity(0.1)).frame(height: 2)
                            Image(systemName: motionSymbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.blue.opacity(0.75))
                                .offset(x: x)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .onChange(of: context.date) { _, _ in if animates { lastPhase = moving } }
                }
                .frame(height: active ? 18 : 0)
                .opacity(active ? 1 : 0)
                .clipped()
                .animation(motion.resultAnimation, value: active)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
        .onAppear { hasStarted = active }
        .onChange(of: animates) { wasActive, nowActive in
            if wasActive && !nowActive { frozenPhase = lastPhase }
            if nowActive { hasStarted = true }
        }
    }
    private var motionSymbol: String {
        switch family {
        case .webSearch, .sourceSearch: "magnifyingglass"
        case .fileOperation: "doc.text"
        case .codeExecution, .command: "chevron.left.forwardslash.chevron.right"
        case .imageGeneration: "photo"
        case .map: "location"
        case .generic: "circle.fill"
        }
    }
}
#endif
