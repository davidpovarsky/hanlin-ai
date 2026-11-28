import HanlinChatUI
import Observation
import SwiftUI
import UIKit

// Same canonical activity control used by the original chat.
private typealias ToggleButton = HanlinActivityToggleButton

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

@MainActor
@Observable
private final class MotionProofTelemetry {
    private(set) var expandedActionCount = 0
    private(set) var geometryStateLabel = "collapsed"
    private(set) var settledNaturalHeight: CGFloat = 0
    private(set) var settledVisibleHeight: CGFloat = 0
    private(set) var scrollOffsetY: CGFloat = 0
    private(set) var isLandscape: Bool?

    @ObservationIgnored private var naturalHeight: CGFloat = 0
    @ObservationIgnored private var visibleHeight: CGFloat = 0
    @ObservationIgnored private var actionUptimes: [TimeInterval] = []
    @ObservationIgnored private var actionAtIntermediate: [Bool] = []
    @ObservationIgnored private var actionVisibleHeights: [CGFloat] = []
    @ObservationIgnored private var samples: [[String: String]] = []
    @ObservationIgnored private var transitionStarted = ProcessInfo.processInfo.systemUptime

    func recordAction(nextExpanded: Bool) {
        let isIntermediate = naturalHeight > 0 && visibleHeight > 0.25 && visibleHeight < naturalHeight + 6 - 0.5
        actionUptimes.append(ProcessInfo.processInfo.systemUptime)
        actionAtIntermediate.append(isIntermediate)
        actionVisibleHeights.append(visibleHeight)
        expandedActionCount += 1
        settledNaturalHeight = naturalHeight
        settledVisibleHeight = visibleHeight
        updateGeometryState(expanded: nextExpanded)
    }

    func noteTransitionStarted() {
        transitionStarted = ProcessInfo.processInfo.systemUptime
    }

    func recordNaturalHeight(_ height: CGFloat, expanded: Bool) {
        guard height == 0 ? naturalHeight != 0 : abs(naturalHeight - height) >= 0.01 else { return }
        naturalHeight = height
        updateGeometryState(expanded: expanded)
    }

    func recordVisibleHeight(_ height: CGFloat, preset: String, expanded: Bool) {
        if samples.count < 16000 {
            samples.append(["preset": preset, "expanded": String(expanded),
                "seconds": String(ProcessInfo.processInfo.systemUptime - transitionStarted),
                "height": String(Double(height)), "natural": String(Double(naturalHeight))])
        }
        guard height == 0 ? visibleHeight != 0 : abs(visibleHeight - height) >= 0.01 else { return }
        visibleHeight = height
        updateGeometryState(expanded: expanded)
    }

    func recordScrollOffset(_ newY: CGFloat) {
        guard newY == 0 ? scrollOffsetY != 0 : abs(scrollOffsetY - newY) >= 0.1 else { return }
        scrollOffsetY = newY
    }

    func recordOrientation(isLandscape: Bool) {
        guard self.isLandscape != isLandscape else { return }
        self.isLandscape = isLandscape
    }

    var orientationLabel: String {
        isLandscape.map { $0 ? "landscape" : "portrait" } ?? "unknown"
    }

    func statusValue(expanded: Bool) -> String {
        "expanded=\(expanded);orientation=\(orientationLabel)"
    }

    func actionReceiptValue(expanded: Bool) -> String {
        // Bound AX historical arrays during long cycle sweeps while retaining full
        // interaction receipts for short reversal tests and full JSON timelines on disk.
        let maxArrayItems = 32
        let allGaps = zip(actionUptimes.dropFirst(), actionUptimes)
            .map { String(format: "%.4f", $0.0 - $0.1) }
        let gaps = (allGaps.count > maxArrayItems ? Array(allGaps.suffix(maxArrayItems)) : allGaps)
            .joined(separator: ",")
        let intermediateSlice = actionAtIntermediate.dropFirst()
        let intermediate = (intermediateSlice.count > maxArrayItems
            ? Array(intermediateSlice.suffix(maxArrayItems))
            : Array(intermediateSlice))
            .map(String.init)
            .joined(separator: ",")
        let visibleSlice = actionVisibleHeights.count > maxArrayItems
            ? Array(actionVisibleHeights.suffix(maxArrayItems))
            : actionVisibleHeights
        let actionVisible = visibleSlice.map { String(format: "%.1f", $0) }.joined(separator: ",")
        return "actions=\(expandedActionCount);expanded=\(expanded);natural=\(settledNaturalHeight);visible=\(settledVisibleHeight);gaps=\(gaps);intermediate=\(intermediate);scrollY=\(String(format: "%.1f", scrollOffsetY));orientation=\(orientationLabel);actionVisible=\(actionVisible)"
    }

    func saveTimeline() {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("motion-geometry-timeline.json"), options: .atomic)
    }

    private func updateGeometryState(expanded: Bool) {
        let next: String
        if !expanded && visibleHeight < 0.25 {
            next = "collapsed"
        } else if expanded && naturalHeight > 0 && abs(visibleHeight - naturalHeight - 6) < 0.5 {
            next = "expanded"
        } else {
            next = "transitioning"
        }
        if geometryStateLabel != next {
            geometryStateLabel = next
        }
        if next != "transitioning" {
            if settledNaturalHeight != naturalHeight { settledNaturalHeight = naturalHeight }
            if settledVisibleHeight != visibleHeight { settledVisibleHeight = visibleHeight }
        }
    }
}

private struct MotionProofGeometryReadout: View {
    let telemetry: MotionProofTelemetry
    let expanded: Bool

    var body: some View {
        Text(telemetry.geometryStateLabel)
            .accessibilityIdentifier("proof-geometry-state")
            .accessibilityValue(telemetry.statusValue(expanded: expanded))
    }
}

private struct MotionProofActionReceiptReadout: View {
    let telemetry: MotionProofTelemetry
    let expanded: Bool

    var body: some View {
        Text("actions=\(telemetry.expandedActionCount)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("proof-action-receipt")
            .accessibilityValue(telemetry.actionReceiptValue(expanded: expanded))
    }
}

private struct MotionProofContent: View {
    @AppStorage(ChatMotionPreset.storageKey) private var storedID = ChatMotionPreset.relaxed.rawValue
    @Environment(\.chatMotion) private var motion
    @State private var expanded = false
    @State private var toolExpanded = false
    @State private var count = 0
    @State private var running = true
    @State private var longText = false
    @State private var rtl = false
    @State private var largeType = false
    @State private var telemetry = MotionProofTelemetry()

    // Observe only writes made by the unchanged production ToggleButton. This
    // distinguishes an undelivered rapid tap from a completed layout reversal.
    private var observedExpansion: Binding<Bool> {
        Binding(get: { expanded }, set: { value in
            telemetry.recordAction(nextExpanded: value)
            expanded = value
        })
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
            HStack(spacing: 12) {
                MotionProofGeometryReadout(telemetry: telemetry, expanded: expanded)
                MotionProofActionReceiptReadout(telemetry: telemetry, expanded: expanded)
            }
            Text("shimmer=\(running && motion.showsShimmer);numeric=\(motion.numericCounts)")
                .accessibilityIdentifier("proof-effective-motion")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Keep header and disclosure in the same lazy row, as in
                    // HanlinActivityDisclosureStyle and the original D production probe.
                    VStack(alignment: .leading, spacing: 0) {
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
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                telemetry.recordNaturalHeight($0, expanded: expanded)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            telemetry.recordVisibleHeight(height, preset: storedID, expanded: expanded)
                        }
                    }
                    Text("Original content after details").padding(.top, 6)
                        .accessibilityIdentifier("proof-footer")
                }.padding()
                .chatScrollImmediateContentTouches()
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, newY in
                telemetry.recordScrollOffset(newY)
            }
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .dynamicTypeSize(largeType ? .accessibility2 : .large)
            Button("Save geometry timeline") { telemetry.saveTimeline() }.accessibilityIdentifier("proof-save-timeline")
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape in
            telemetry.recordOrientation(isLandscape: isLandscape)
        }
        .onChange(of: expanded) { _, _ in telemetry.noteTransitionStarted() }
    }
}

// Opt-in input experiment only. The normal Motion proof screen and production
// component bodies stay unchanged; this screen provides native reference controls.
@MainActor
@Observable
private final class RapidInputDiagnosticModel {
    struct ProbeState: Codable {
        var expanded = false
        var visible: CGFloat = 0
        var natural: CGFloat = 0
    }

    struct Sample: Codable {
        let control: String
        let uptime: TimeInterval
        let wasExpanded: Bool?
        let isExpanded: Bool?
        let visibleHeight: Double?
        let naturalHeight: Double?
    }

    private(set) var expandedStates: [String: Bool] = ["static": false, "animated": false]
    private(set) var geometryStatus = "static=collapsed;animated=collapsed"
    private(set) var geometryReceiptJSON = "{}"
    private(set) var sampleCount = 0
    private(set) var receiptJSON = "[]"
    var disablesScrollTouchDelay = false
    var scrollConfiguration: MotionScrollTouchConfiguration?

    @ObservationIgnored private var probes: [String: ProbeState] = ["static": ProbeState(), "animated": ProbeState()]
    @ObservationIgnored private var samples: [Sample] = []

    func isExpanded(_ key: String) -> Bool {
        expandedStates[key] ?? false
    }

    func setExpanded(_ key: String, _ value: Bool, control: String) {
        let state = probes[key] ?? ProbeState()
        samples.append(Sample(
            control: control,
            uptime: ProcessInfo.processInfo.systemUptime,
            wasExpanded: state.expanded,
            isExpanded: value,
            visibleHeight: Double(state.visible),
            naturalHeight: Double(state.natural)
        ))
        probes[key]?.expanded = value
        expandedStates[key] = value
        syncSampleReceipt()
        refreshGeometry(forceReceiptUpdate: true)
    }

    func recordNativeTap(control: String) {
        samples.append(Sample(
            control: control,
            uptime: ProcessInfo.processInfo.systemUptime,
            wasExpanded: nil,
            isExpanded: nil,
            visibleHeight: nil,
            naturalHeight: nil
        ))
        syncSampleReceipt()
    }

    func reset() {
        samples.removeAll()
        for key in ["static", "animated"] {
            probes[key]?.expanded = false
            expandedStates[key] = false
        }
        syncSampleReceipt()
        refreshGeometry(forceReceiptUpdate: true)
    }

    func recordNaturalHeight(_ key: String, _ height: CGFloat) {
        guard let current = probes[key],
              (height == 0 ? current.natural != 0 : abs(current.natural - height) >= 0.01) else { return }
        probes[key]?.natural = height
        refreshGeometry(forceReceiptUpdate: false)
    }

    func recordVisibleHeight(_ key: String, _ height: CGFloat) {
        guard let current = probes[key],
              (height == 0 ? current.visible != 0 : abs(current.visible - height) >= 0.01) else { return }
        probes[key]?.visible = height
        refreshGeometry(forceReceiptUpdate: false)
    }

    var scrollConfigurationJSON: String {
        guard let scrollConfiguration,
              let data = try? JSONEncoder().encode(scrollConfiguration) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func geometryState(for state: ProbeState) -> String {
        if !state.expanded && state.visible < 0.25 { return "collapsed" }
        if state.expanded && state.natural > 0 && abs(state.visible - state.natural - 6) < 0.5 {
            return "expanded"
        }
        return "transitioning"
    }

    private func refreshGeometry(forceReceiptUpdate: Bool) {
        let staticState = geometryState(for: probes["static"] ?? ProbeState())
        let animatedState = geometryState(for: probes["animated"] ?? ProbeState())
        let nextStatus = "static=\(staticState);animated=\(animatedState)"
        let statusChanged = geometryStatus != nextStatus
        if statusChanged {
            geometryStatus = nextStatus
        }
        // Keep intermediate frames off the AX tree; refresh receipt JSON on action, reset, or settle.
        if forceReceiptUpdate || statusChanged || (staticState != "transitioning" && animatedState != "transitioning") {
            let encoded = encodeJSON(probes, fallback: "{}")
            if geometryReceiptJSON != encoded {
                geometryReceiptJSON = encoded
            }
        }
    }

    private func syncSampleReceipt() {
        sampleCount = samples.count
        receiptJSON = encodeJSON(samples, fallback: "[]")
    }

    private func encodeJSON<T: Encodable>(_ value: T, fallback: String) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return fallback }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct RapidInputScrollConfigurationReadout: View {
    let model: RapidInputDiagnosticModel

    var body: some View {
        Text("Scroll input configuration").lineLimit(1).frame(height: 24)
            .accessibilityIdentifier("rapid-scroll-configuration")
            .accessibilityLabel(model.scrollConfiguration?.phase ?? "unresolved")
            .accessibilityValue(model.scrollConfigurationJSON)
    }
}

private struct RapidInputSamplesReceiptReadout: View {
    let model: RapidInputDiagnosticModel

    var body: some View {
        Text("Input diagnostic samples").lineLimit(1).frame(height: 24)
            .accessibilityIdentifier("rapid-input-receipt")
            .accessibilityLabel(String(model.sampleCount))
            .accessibilityValue(model.receiptJSON)
    }
}

private struct RapidInputGeometryStatusReadout: View {
    let model: RapidInputDiagnosticModel

    var body: some View {
        Text(model.geometryStatus).lineLimit(1).frame(height: 24)
            .accessibilityIdentifier("rapid-input-geometry")
    }
}

private struct RapidInputGeometryReceiptReadout: View {
    let model: RapidInputDiagnosticModel

    var body: some View {
        Text("Geometry receipt").lineLimit(1).frame(height: 24)
            .accessibilityIdentifier("rapid-input-geometry-receipt")
            .accessibilityValue(model.geometryReceiptJSON)
    }
}

private struct MotionRapidInputDiagnostic: View {
    @State private var model = RapidInputDiagnosticModel()

    private func observed(_ key: String) -> Binding<Bool> {
        Binding(get: { model.isExpanded(key) }, set: { value in
            model.setExpanded(key, value, control: "rapid-production-\(key)")
        })
    }

    private func nativeButton(_ title: String, id: String) -> some View {
        Button {
            model.recordNativeTap(control: id)
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
            HanlinAnimatedDisclosure(isExpanded: model.isExpanded(key)) {
                Text("Diagnostic disclosure content\nSecond visible line\nThird visible line")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        model.recordNaturalHeight(key, $0)
                    }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                model.recordVisibleHeight(key, $0)
            }
        }
        .environment(\.chatMotion, .forPreset(preset))
    }

    var body: some View {
        VStack(spacing: 8) {
            Button("Reset input observations") {
                model.reset()
            }
            .accessibilityIdentifier("rapid-input-reset")
            Button(model.disablesScrollTouchDelay ? "Restore original scroll touches" : "Use immediate scroll touches") {
                model.disablesScrollTouchDelay.toggle()
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
                    MotionScrollTouchProbe(disableDelay: model.disablesScrollTouchDelay) {
                        model.scrollConfiguration = $0
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            RapidInputScrollConfigurationReadout(model: model)
            RapidInputSamplesReceiptReadout(model: model)
            HStack(spacing: 8) {
                RapidInputGeometryStatusReadout(model: model)
                RapidInputGeometryReceiptReadout(model: model)
            }
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
