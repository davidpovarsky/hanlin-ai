import SwiftUI
import UIKit

@main
struct MotionProofApp: App {
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--reset-motion") {
            UserDefaults.standard.removeObject(forKey: ChatMotionPreset.storageKey)
        }
        if arguments.contains("--invalid-motion") {
            UserDefaults.standard.set("v9.corrupt", forKey: ChatMotionPreset.storageKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--rapid-input-diagnostic") {
                MotionRapidInputDiagnostic().chatMotionPreferences()
            } else {
                MotionProofContent().chatMotionPreferences()
            }
        }
    }
}

private struct MotionProofContent: View {
    @AppStorage(ChatMotionPreset.storageKey) private var storedID = ChatMotionPreset.relaxed.rawValue
    @Environment(\.chatMotion) private var motion
    @State private var expanded = false
    @State private var expandedActionCount = 0
    @State private var toolExpanded = false
    @State private var count = 0
    @State private var running = true
    @State private var longText = false
    @State private var rtl = false
    @State private var largeType = false
    @State private var naturalHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var samples: [[String: String]] = []
    @State private var transitionStarted = ProcessInfo.processInfo.systemUptime
    @State private var actionUptimes: [TimeInterval] = []
    @State private var actionAtIntermediate: [Bool] = []
    @State private var scrollOffsetY: CGFloat = 0

    // Observe only writes made by the unchanged production ToggleButton. This
    // distinguishes an undelivered rapid tap from a completed layout reversal.
    private var observedExpansion: Binding<Bool> {
        Binding(get: { expanded }, set: { value in
            let isIntermediate = naturalHeight > 0 && visibleHeight > 0.25 && visibleHeight < naturalHeight + 6 - 0.5
            actionUptimes.append(ProcessInfo.processInfo.systemUptime)
            actionAtIntermediate.append(isIntermediate)
            expandedActionCount += 1
            expanded = value
        })
    }

    private var actionReceiptValue: String {
        let gaps = zip(actionUptimes.dropFirst(), actionUptimes)
            .map { String(format: "%.4f", $0.0 - $0.1) }
            .joined(separator: ",")
        let intermediate = actionAtIntermediate.dropFirst().map(String.init).joined(separator: ",")
        return "actions=\(expandedActionCount);expanded=\(expanded);natural=\(naturalHeight);visible=\(visibleHeight);gaps=\(gaps);intermediate=\(intermediate);scrollY=\(String(format: "%.1f", scrollOffsetY))"
    }

    private var geometryState: String {
        if !expanded && visibleHeight < 0.25 { return "collapsed" }
        if expanded && naturalHeight > 0 && abs(visibleHeight - naturalHeight - 6) < 0.5 { return "expanded" }
        return "transitioning"
    }

    var body: some View {
        VStack(spacing: 8) {
            Form { ChatMotionPresetPicker() }.frame(height: 100)
            Text(storedID).accessibilityIdentifier("proof-persisted-preset")
            HStack {
                Button("Count") { count = count == 0 ? 1 : count == 1 ? 17 : 100 }
                    .accessibilityIdentifier("proof-count")
                Button("Finish") { running = false }.accessibilityIdentifier("proof-finish")
                Button("Long text") { longText.toggle() }.accessibilityIdentifier("proof-long")
                Button("RTL") { rtl.toggle() }.accessibilityIdentifier("proof-rtl")
                Button("Large type") { largeType.toggle() }.accessibilityIdentifier("proof-type")
            }.buttonStyle(.bordered)
            Text(geometryState).accessibilityIdentifier("proof-geometry-state")
                .accessibilityValue(actionReceiptValue)
            Text("shimmer=\(running && motion.showsShimmer);numeric=\(motion.numericCounts)")
                .accessibilityIdentifier("proof-effective-motion")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Exact original production ToggleButton, visibility lifted only by the preparer.
                    ToggleButton(title: "Thinking", timeText: String(count), isExpanded: observedExpansion,
                        isActive: running, numericCount: count, usesAnimatedDisclosure: true)
                        .accessibilityIdentifier("proof-thinking")
                    HanlinAnimatedDisclosure(isExpanded: expanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A short visible reasoning summary. שלום עולם. مرحبًا بالعالم.")
                                .textSelection(.enabled).accessibilityIdentifier("proof-summary")
                            if longText {
                                Text(String(repeating: "**Markdown** `code()` שלום مرحبًا\n", count: 24))
                                    .font(.body).textSelection(.enabled)
                            }
                            DisclosureGroup(isExpanded: $toolExpanded) {
                                Text("Tool output, not hidden reasoning.\nlet value = 17")
                                    .font(.body.monospaced()).textSelection(.enabled)
                                    .accessibilityIdentifier("proof-tool-output")
                            } label: { Text("Repeated tool name") }
                                .disclosureGroupStyle(HanlinMotionDisclosureStyle())
                            Text("source call-2: Repeated tool name — cancelled")
                            Text("source call-3: Repeated tool name — failed; no output")
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { naturalHeight = $0 }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        visibleHeight = height
                        if samples.count < 16000 {
                            samples.append(["preset": storedID, "expanded": String(expanded),
                                "seconds": String(ProcessInfo.processInfo.systemUptime - transitionStarted),
                                "height": String(Double(height)), "natural": String(Double(naturalHeight))])
                        }
                    }
                    Text("Original content after details").padding(.top, 6)
                        .accessibilityIdentifier("proof-footer")
                }.padding()
                .chatScrollImmediateContentTouches()
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, newY in
                scrollOffsetY = newY
            }
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .dynamicTypeSize(largeType ? .accessibility2 : .large)
            Button("Save geometry timeline") { saveTimeline() }.accessibilityIdentifier("proof-save-timeline")
        }
        .onChange(of: expanded) { _, _ in transitionStarted = ProcessInfo.processInfo.systemUptime }
    }

    private func saveTimeline() {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("motion-geometry-timeline.json"), options: .atomic)
    }
}

// Opt-in input experiment only. The normal Motion proof screen and production
// component bodies stay unchanged; this screen provides native reference controls.
private struct MotionRapidInputDiagnostic: View {
    private struct ProbeState: Codable {
        var expanded = false
        var visible: CGFloat = 0
        var natural: CGFloat = 0
    }
    private struct Sample: Codable {
        let control: String
        let uptime: TimeInterval
        let wasExpanded: Bool?
        let isExpanded: Bool?
        let visibleHeight: Double?
        let naturalHeight: Double?
    }
    @State private var probes = ["static": ProbeState(), "animated": ProbeState()]
    @State private var samples: [Sample] = []
    @State private var disablesScrollTouchDelay = false
    @State private var scrollConfiguration: MotionScrollTouchConfiguration?

    private var scrollConfigurationJSON: String {
        guard let scrollConfiguration,
              let data = try? JSONEncoder().encode(scrollConfiguration) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private var receiptJSON: String {
        guard let data = try? JSONEncoder().encode(samples) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private var geometryReceiptJSON: String {
        guard let data = try? JSONEncoder().encode(probes) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func geometry(_ key: String) -> String {
        let state = probes[key]!
        if !state.expanded && state.visible < 0.25 { return "collapsed" }
        if state.expanded && state.natural > 0 && abs(state.visible - state.natural - 6) < 0.5 {
            return "expanded"
        }
        return "transitioning"
    }

    private func observed(_ key: String) -> Binding<Bool> {
        Binding(get: { probes[key]!.expanded }, set: { value in
            let state = probes[key]!
            samples.append(Sample(control: "rapid-production-\(key)",
                uptime: ProcessInfo.processInfo.systemUptime,
                wasExpanded: state.expanded, isExpanded: value,
                visibleHeight: Double(state.visible), naturalHeight: Double(state.natural)))
            probes[key]!.expanded = value
        })
    }

    private func nativeButton(_ title: String, id: String) -> some View {
        Button {
            samples.append(Sample(control: id, uptime: ProcessInfo.processInfo.systemUptime,
                wasExpanded: nil, isExpanded: nil, visibleHeight: nil, naturalHeight: nil))
        } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }

    private func productionProbe(_ key: String, preset: ChatMotionPreset) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleButton(title: "Thinking", timeText: "0", isExpanded: observed(key),
                isActive: true, numericCount: 0, usesAnimatedDisclosure: true)
                .accessibilityIdentifier("rapid-production-\(key)")
            HanlinAnimatedDisclosure(isExpanded: probes[key]!.expanded) {
                Text("Diagnostic disclosure content\nSecond visible line\nThird visible line")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        probes[key]!.natural = $0
                    }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                probes[key]!.visible = $0
            }
        }
        .environment(\.chatMotion, .forPreset(preset))
    }

    var body: some View {
        VStack(spacing: 8) {
            Button("Reset input observations") {
                samples.removeAll()
                for key in ["static", "animated"] { probes[key]!.expanded = false }
            }
            .accessibilityIdentifier("rapid-input-reset")
            Button(disablesScrollTouchDelay ? "Restore original scroll touches" : "Use immediate scroll touches") {
                disablesScrollTouchDelay.toggle()
            }
            .accessibilityIdentifier("rapid-scroll-delay-toggle")
            nativeButton("Native button outside ScrollView", id: "rapid-native-outside")
                .padding(.horizontal)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    nativeButton("Native automatic button", id: "rapid-native-scroll")
                    nativeButton("Native plain button", id: "rapid-native-plain").buttonStyle(.plain)
                    productionProbe("static", preset: .none)
                    productionProbe("animated", preset: .relaxed)
                }.padding()
                .background {
                    MotionScrollTouchProbe(disableDelay: disablesScrollTouchDelay) {
                        scrollConfiguration = $0
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            Text("Scroll input configuration").lineLimit(1).frame(height: 24)
                .accessibilityIdentifier("rapid-scroll-configuration")
                .accessibilityLabel(scrollConfiguration?.phase ?? "unresolved")
                .accessibilityValue(scrollConfigurationJSON)
            Text("Input diagnostic samples").lineLimit(1).frame(height: 24)
                .accessibilityIdentifier("rapid-input-receipt")
                .accessibilityLabel(String(samples.count))
                .accessibilityValue(receiptJSON)
            Text("static=\(geometry("static"));animated=\(geometry("animated"))")
                .lineLimit(1).frame(height: 24)
                .accessibilityIdentifier("rapid-input-geometry")
                .accessibilityValue(geometryReceiptJSON)
        }
    }
}


// This opt-in diagnostic changes only the public touch-delay property on the
// actual containing scroll view. Production screens and acceptance B are unchanged.
private struct MotionScrollTouchConfiguration: Codable, Equatable {
    let phase: String
    let originalDelaysContentTouches: Bool
    let delaysContentTouches: Bool
    let canCancelContentTouches: Bool
    let isScrollEnabled: Bool
}

@MainActor
private struct MotionScrollTouchProbe: UIViewRepresentable {
    var disableDelay: Bool
    var onConfiguration: (MotionScrollTouchConfiguration) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.disableDelay = disableDelay
        view.onConfiguration = onConfiguration
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.disableDelay = disableDelay
        uiView.onConfiguration = onConfiguration
        uiView.applyConfiguration()
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: ()) {
        uiView.restoreOriginalSettings()
    }

    final class ProbeView: UIView {
        var disableDelay = false
        var onConfiguration: ((MotionScrollTouchConfiguration) -> Void)?
        private weak var observedScrollView: UIScrollView?
        private var originalDelay: Bool?
        private var lastConfiguration: MotionScrollTouchConfiguration?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { restoreOriginalSettings() }
            else { applyConfiguration() }
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            applyConfiguration()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyConfiguration()
        }

        func restoreOriginalSettings() {
            if let scrollView = observedScrollView, let originalDelay {
                scrollView.delaysContentTouches = originalDelay
            }
            observedScrollView = nil
            originalDelay = nil
            lastConfiguration = nil
        }

        func applyConfiguration() {
            guard window != nil else { return }
            var ancestor = superview
            var containingScrollView: UIScrollView?
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    containingScrollView = scrollView
                    break
                }
                ancestor = view.superview
            }
            guard let scrollView = containingScrollView else { return }
            if observedScrollView !== scrollView {
                restoreOriginalSettings()
                observedScrollView = scrollView
                originalDelay = scrollView.delaysContentTouches
            }
            guard let originalDelay else { return }
            let requestedDelay = disableDelay ? false : originalDelay
            if scrollView.delaysContentTouches != requestedDelay {
                scrollView.delaysContentTouches = requestedDelay
            }
            // Do not alter cancellation, pan recognition, scroll enablement or
            // control actions. The test records and checks these native flags.
            let configuration = MotionScrollTouchConfiguration(
                phase: disableDelay ? "immediate-touch-down" : "native-default",
                originalDelaysContentTouches: originalDelay,
                delaysContentTouches: scrollView.delaysContentTouches,
                canCancelContentTouches: scrollView.canCancelContentTouches,
                isScrollEnabled: scrollView.isScrollEnabled)
            guard configuration != lastConfiguration else { return }
            lastConfiguration = configuration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, let latest = self.lastConfiguration else { return }
                self.onConfiguration?(latest)
            }
        }
    }
}
