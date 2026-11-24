import HanlinLocalization
#if canImport(SwiftUI)
import SwiftUI
import HanlinPresentationKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// V17's live surface and compact result share one call identity. Only trusted
/// execution families select motion, and source counts contain observed URLs.
public struct HanlinToolActivityHeader: View {
    public enum Family: String, Sendable {
        case generic, webSearch, fileOperation, codeExecution, command, sourceSearch, imageGeneration, map
    }
    private let title: String
    private let status: String
    private let symbol: String
    private let family: Family
    private let active: Bool
    private let shimmerActive: Bool
    private let expanded: Bool
    private let isFailure: Bool
    private let isCancelled: Bool
    private let sources: [HanlinSourceReference]
    private let completedAt: Date?
    private let icons: HanlinToolIconSet?

    @Environment(\.chatMotion) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.hanlinActivityBranchVisible) private var branchIsVisible
    @Environment(\.layoutDirection) private var direction
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .footnote) private var liveFontSize: CGFloat = 14
    @State private var liveSurfaceMounted: Bool
    @State private var liveOpacity: Double
    @State private var startedAt: Date
    @State private var stoppedAt: Date?
    @State private var loadedIconURL: URL?
    @State private var loadedIconData: Data?

    @Environment(\.hanlinChatAppearance) private var appearance
    private var blue: Color { appearance.toolAccent ?? Color(red: 0.28, green: 0.49, blue: 0.80) }

    public init(title: String, status: String, symbol: String, family: Family = .generic,
                isActive: Bool, showsShimmer: Bool? = nil, isExpanded: Bool = false, isFailure: Bool = false,
                isCancelled: Bool = false,
                startedAt: Date? = nil, completedAt: Date? = nil,
                sources: [HanlinSourceReference] = [], icons: HanlinToolIconSet? = nil) {
        self.title = title; self.status = status; self.symbol = symbol
        self.family = family; self.active = isActive; self.expanded = isExpanded
        self.shimmerActive = showsShimmer ?? isActive
        self.isFailure = isFailure; self.isCancelled = isCancelled
        self.sources = sources; self.completedAt = completedAt
        self.icons = icons
        let hasSurface = isActive && Self.supportsLiveSurface(family)
        _liveSurfaceMounted = State(initialValue: hasSurface)
        _liveOpacity = State(initialValue: hasSurface ? 1 : 0)
        _startedAt = State(initialValue: startedAt ?? Date())
    }

    private static func supportsLiveSurface(_ family: Family) -> Bool {
        switch family {
        case .webSearch, .sourceSearch, .codeExecution, .command, .map: true
        // A file percentage, flight path or price requires structured Host
        // progress. Never substitute a demo timer or invent those semantics.
        default: false
        }
    }

    private var showsLiveSurface: Bool { active && Self.supportsLiveSurface(family) }
    private var animates: Bool {
        active && branchIsVisible && motion.isAnimated && !reduceMotion && !voiceOver && scenePhase == .active
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            compactTitle
                .opacity(1 - liveOpacity)
                .accessibilityHidden(liveSurfaceMounted && liveOpacity > 0.5)
            if liveSurfaceMounted {
                liveSurface
                    .opacity(liveOpacity)
                    .accessibilityHidden(liveOpacity <= 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: iconCandidates) { await loadDeclaredIcon() }
        .task(id: showsLiveSurface) {
            if showsLiveSurface {
                stoppedAt = nil
                liveSurfaceMounted = true
                withAnimation(motion.resultAnimation) { liveOpacity = 1 }
            } else {
                guard liveSurfaceMounted else { return }
                // Capture the current clock position, fade it in place, then
                // unmount. There is no final lap or zero-width collapse.
                stoppedAt = completedAt ?? Date()
                if !motion.isAnimated || reduceMotion || voiceOver || !branchIsVisible {
                    liveOpacity = 0
                    liveSurfaceMounted = false
                    return
                }
                withAnimation(motion.resultAnimation) { liveOpacity = 0 }
                do { try await Task.sleep(for: .seconds(motion.resultDuration)) }
                catch { return }
                guard !Task.isCancelled else { return }
                liveSurfaceMounted = false
            }
        }
        .onChange(of: animates) { _, running in
            if running { stoppedAt = nil }
            else if stoppedAt == nil { stoppedAt = completedAt ?? Date() }
        }
    }

    private var compactTitle: some View {
        HStack(spacing: 8) {
            toolIcon(color: iconColor, width: 20)
            HanlinActivityTitle(title, font: HanlinTypography.subheadline,
                baseColor: Color.primary.opacity(0.71),
                isActive: active && shimmerActive && !Self.supportsLiveSurface(family))
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            HanlinActivityDisclosureArrow(isExpanded: expanded)
            Spacer(minLength: 2)
            if !sources.isEmpty {
                sourceIcons(compact: true)
                sourceCount
            }
            if !status.isEmpty {
                if isFailure {
                    Image(systemName: "exclamationmark.circle")
                        .font(HanlinTypography.footnote.weight(.medium))
                        .foregroundStyle(Color(red: 0.69, green: 0.40, blue: 0.26))
                        .accessibilityHidden(true)
                } else if isCancelled {
                    Image(systemName: "minus.circle")
                        .font(HanlinTypography.footnote)
                        .foregroundStyle(Color.secondary.opacity(0.70))
                        .accessibilityHidden(true)
                }
                Text(status).font(HanlinTypography.caption.weight(.medium))
                    .foregroundStyle(isFailure
                        ? Color(red: 0.60, green: 0.39, blue: 0.31) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 41)
    }

    private var iconColor: Color {
        switch family {
        case .webSearch, .sourceSearch, .map: blue
        case .fileOperation: Color(red: 0.40, green: 0.50, blue: 0.70)
        default: .gray
        }
    }

    private var iconCandidates: [URL] {
        icons?.candidateURLs(for: colorScheme == .dark ? .dark : .light) ?? []
    }

    private var declaredIcon: Image? {
        guard let loadedIconURL, iconCandidates.contains(loadedIconURL),
              let loadedIconData else { return nil }
        #if canImport(UIKit)
        return UIImage(data: loadedIconData).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: loadedIconData).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }

    private func toolIcon(color: Color, width: CGFloat) -> some View {
        Group {
            if let declaredIcon {
                declaredIcon.resizable().scaledToFit()
            } else {
                Image(systemName: symbol)
                    .font(HanlinTypography.body.weight(.medium))
                    .foregroundStyle(color)
            }
        }
        .frame(width: width, height: 22)
        .accessibilityHidden(true)
    }

    private func loadDeclaredIcon() async {
        let candidates = iconCandidates
        if loadedIconURL == candidates.first, loadedIconData != nil { return }
        loadedIconURL = nil; loadedIconData = nil
        // At most two tool URLs then two server URLs. The original symbol
        // remains visible throughout loading, rejection and network failure.
        for url in candidates {
            guard !Task.isCancelled else { return }
            guard let data = try? await HanlinIconThumbnailLoader.png(from: url) else { continue }
            guard !Task.isCancelled, candidates == iconCandidates else { return }
            loadedIconURL = url; loadedIconData = data
            return
        }
    }

    private var liveSurface: some View {
        HStack(spacing: 8) {
            toolIcon(color: blue, width: 19)
            HanlinActivityTitle(title,
                font: HanlinTypography.fixed(size: liveFontSize, weight: .medium),
                baseColor: Color(red: 0.25, green: 0.37, blue: 0.54),
                isActive: active && shimmerActive, startedAt: startedAt, stoppedAt: stoppedAt)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            HanlinActivityDisclosureArrow(isExpanded: expanded)
            Spacer(minLength: 3)
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animates)) { context in
                let seconds = max(0, (stoppedAt ?? context.date).timeIntervalSince(startedAt))
                if family == .webSearch || family == .sourceSearch {
                    webScanner(seconds: seconds)
                        .frame(minWidth: 32, idealWidth: 168, maxWidth: 168)
                } else {
                    networkPulse(seconds: seconds)
                        .frame(width: 68, height: 27)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(minHeight: 47)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(appearance.toolSurface ?? Color(red: 0.952, green: 0.971, blue: 0.990)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(blue.opacity(0.12), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }

    private var sourceCount: some View {
        Text("\(sources.count)", bundle: HanlinLocalization.bundle)
            .font(HanlinTypography.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(active ? blue : .secondary)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
            .contentTransition(motion.numericCounts ? .numericText(value: Double(sources.count)) : .opacity)
            .animation(motion.updateAnimation, value: sources.count)
            .accessibilityLabel(Text("Sources: \(sources.count)", bundle: HanlinLocalization.bundle))
    }

    private func sourceIcons(compact: Bool) -> some View {
        // A small bounded stack preserves the screenshot's overlapping icons
        // without mounting another ScrollView inside an animated disclosure.
        // The adjacent real count and the details retain the complete list.
        HStack(spacing: -7) {
            ForEach(compact ? Array(sources.prefix(8)) : Array(sources.suffix(6))) { source in
                AsyncImage(url: source.iconURL) { image in image.resizable().scaledToFit() }
                placeholder: {
                    Image(systemName: "globe").font(HanlinTypography.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 17, height: 17)
                .padding(3)
                .background(.white, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 2)
        .frame(minWidth: 0, idealWidth: min(CGFloat(sources.count) * 16 + 11, compact ? 146 : 120),
            maxWidth: compact ? 146 : 120, alignment: .leading)
        .frame(height: 29)
        .clipped()
    }

    private func webScanner(seconds: Double) -> some View {
        HStack(spacing: 5) {
            sourceIcons(compact: false)
            sourceCount
        }
        .padding(.horizontal, 5)
        .frame(height: 31)
        .background {
            GeometryReader { geometry in
                let cycle = seconds.truncatingRemainder(dividingBy: 2.6) / 2.6
                let progress = direction == .rightToLeft ? 1 - cycle : cycle
                let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
                let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
                LinearGradient(colors: [.clear, blue.opacity(0.10), .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(width: 44, height: height)
                    .offset(x: CGFloat(progress) * (width + 44) - 44)
            }
        }
        .clipShape(Capsule())
    }

    private func networkPulse(seconds: Double) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                let wave = 0.4 + 0.6 * abs(sin(seconds * 2.7 + Double(index) * 0.75))
                Capsule().fill(blue.opacity(0.20 + wave * 0.6))
                    .frame(width: 5, height: CGFloat(6 + wave * 12))
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
