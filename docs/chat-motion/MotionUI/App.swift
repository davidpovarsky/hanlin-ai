import SwiftUI

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
        WindowGroup { MotionProofContent().chatMotionPreferences() }
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

    // Observe only writes made by the unchanged production ToggleButton. This
    // distinguishes an undelivered rapid tap from a completed layout reversal.
    private var observedExpansion: Binding<Bool> {
        Binding(get: { expanded }, set: { value in
            expandedActionCount += 1
            expanded = value
        })
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
                .accessibilityValue("actions=\(expandedActionCount);expanded=\(expanded);natural=\(naturalHeight);visible=\(visibleHeight)")
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
