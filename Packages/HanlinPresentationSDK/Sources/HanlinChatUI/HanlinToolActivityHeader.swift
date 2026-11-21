#if canImport(SwiftUI)
import SwiftUI
import HanlinPresentationKit

/// A compact V17 activity surface driven only by the Host's real lifecycle.
/// Family motion is decorative: there are no simulated results or percentages.
public struct HanlinToolActivityHeader: View {
    public enum Family: String, Sendable { case generic, webSearch, fileOperation, codeExecution, command, sourceSearch, imageGeneration, map }
    private let title: String
    private let status: String
    private let symbol: String
    private let family: Family
    private let active: Bool
    private let sources: [HanlinSourceReference]
    @Environment(\.chatMotion) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.layoutDirection) private var direction
    @State private var stoppedAt: Date?

    public init(title: String, status: String, symbol: String, family: Family = .generic,
                isActive: Bool, sources: [HanlinSourceReference] = []) {
        self.title = title; self.status = status; self.symbol = symbol
        self.family = family; self.active = isActive; self.sources = sources
    }

    private var animates: Bool { active && motion.isAnimated && !reduceMotion && !voiceOver && scenePhase == .active }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(HanlinTypography.subheadline)
                .foregroundStyle(active ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(HanlinTypography.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .chatShimmer(isActive: animates)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if !status.isEmpty {
                    Text(status).font(HanlinTypography.caption2).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                if !sources.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(sources.prefix(3))) { source in
                            AsyncImage(url: source.iconURL) { image in image.resizable().scaledToFit() }
                                placeholder: { Image(systemName: "globe").foregroundStyle(.secondary) }
                                .frame(width: 14, height: 14).accessibilityHidden(true)
                        }
                        Text("\(sources.count)").font(HanlinTypography.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 5)
                    .frame(minHeight: 28)
                    .background {
                        if family == .webSearch || family == .sourceSearch {
                            clockDrivenMotion(scannerOnly: true)
                        }
                    }
                    .clipShape(Capsule())
                    .accessibilityLabel(Text("Sources: \(sources.count)"))
                }
            }
            if sources.isEmpty && (active || stoppedAt != nil) {
                if motion.isAnimated && !reduceMotion && !voiceOver {
                    clockDrivenMotion(scannerOnly: false)
                        .frame(width: active ? 56 : 0, height: 27)
                        .clipped()
                } else if active {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, active ? 10 : 0)
        .padding(.vertical, 8)
        .frame(minHeight: active ? 47 : 40)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(active ? 0.055 : 0))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(active ? 0.12 : 0), lineWidth: 0.8)
                }
        }
        .animation(motion.resultAnimation, value: active)
        .animation(motion.updateAnimation, value: status)
        .onChange(of: animates) { _, nowAnimating in
            // Freeze at the actual lifecycle transition, then fade in place.
            stoppedAt = nowAnimating ? nil : Date()
        }
    }

    private func clockDrivenMotion(scannerOnly: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animates)) { context in
            // Read the clock only inside the decorative subtree. A frame never
            // writes @State and never invalidates the conversation hierarchy.
            let date = stoppedAt ?? context.date
            let seconds = date.timeIntervalSinceReferenceDate
            if scannerOnly {
                scanner(seconds: seconds)
            } else {
                activityMotion(seconds: seconds)
            }
        }
        .opacity(active ? 1 : 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func activityMotion(seconds: Double) -> some View {
        switch family {
        case .webSearch, .sourceSearch:
            Image(systemName: "magnifyingglass")
                .font(HanlinTypography.caption).foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { scanner(seconds: seconds) }
                .clipShape(Capsule())
        case .fileOperation:
            // The Host does not provide a byte fraction here. A scanning page
            // conveys activity without inventing a completion percentage.
            Image(systemName: "doc.text")
                .font(HanlinTypography.callout).foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { scanner(seconds: seconds) }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        default:
            // V17's compact network pulse is intentionally decorative.
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    let wave = 0.4 + 0.6 * abs(sin(seconds * 2.7 + Double(index) * 0.75))
                    Capsule().fill(Color.accentColor.opacity(0.20 + wave * 0.6))
                        .frame(width: 5, height: CGFloat(6 + wave * 12))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scanner(seconds: Double) -> some View {
        GeometryReader { geometry in
            let phase = seconds.truncatingRemainder(dividingBy: 2.6) / 2.6
            let progress = direction == .rightToLeft ? 1 - phase : phase
            LinearGradient(colors: [.clear, Color.accentColor.opacity(0.10), .clear],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: 44, height: geometry.size.height)
                .offset(x: progress * (geometry.size.width + 44) - 44)
        }
    }
}
#endif
