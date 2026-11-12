import SwiftUI
import UIKit

struct ChatCodeFenceView: View {
    let blockID: String
    let kind: String
    let source: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var payload: ChatCodeFencePayload?
    @State private var showsSource = false
    @State private var expanded = false
    @State private var split = false
    @State private var canSplit = false
    @State private var failed = false
    @State private var requiresRestart = false
    @State private var retry = 0

    private struct Request: Hashable {
        let source: String
        let kind: String
        let dark: Bool
        let fontSize: Double
        let split: Bool
        let retry: Int
    }
    private var request: Request {
        let _ = dynamicTypeSize
        return Request(source: source, kind: kind, dark: colorScheme == .dark,
                       fontSize: Double(UIFont.preferredFont(forTextStyle: .callout).pointSize), split: split, retry: retry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind == "mermaid" ? String(localized: "Diagram") : String(localized: "Code comparison"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Toggle(String(localized: "Show code"), isOn: $showsSource).toggleStyle(.button).font(.caption)
                Menu {
                    Button(String(localized: "Copy source"), systemImage: "doc.on.doc") { UIPasteboard.general.string = source }
                    ShareLink(item: source) { Label(String(localized: "Share source"), systemImage: "square.and.arrow.up") }
                    Button(String(localized: "Expand"), systemImage: "arrow.up.left.and.arrow.down.right") { expanded = true }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "Code block actions")) }
            }
            if kind == "diff", canSplit {
                Picker(String(localized: "Comparison layout"), selection: $split) {
                    Text(String(localized: "Unified")).tag(false)
                    Text(String(localized: "Side by side")).tag(true)
                }.pickerStyle(.segmented)
            }
            if showsSource || failed {
                sourcePreview
            } else if let payload {
                ChatCodeFenceWebView(payload: payload)
                    .frame(height: min(480, max(120, payload.height + 8)))
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                ProgressView(String(localized: "Rendering preview"))
                    .frame(maxWidth: .infinity, minHeight: 96)
            }
            if failed {
                Text(requiresRestart
                     ? String(localized: "The preview stopped responding. Reopen the app to try again. You can still read or share the source.")
                     : String(localized: "Preview is unavailable. The complete source remains available to copy, share or expand."))
                    .font(.caption).foregroundStyle(.secondary)
                if !requiresRestart {
                    Button(String(localized: "Retry preview")) { failed = false; retry += 1 }
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-code-fence-\(kind)-\(blockID)")
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide in
            canSplit = wide
            if !wide { split = false }
        }
        .task(id: request) {
            let current = request
            payload = nil
            failed = false
            do {
                try await Task.sleep(for: .milliseconds(250))
                let started = ContinuousClock.now
                let result = try await ChatCodeFenceEngine.shared.render(kind: current.kind, source: current.source,
                    dark: current.dark, fontSize: current.fontSize, split: current.split)
                try Task.checkCancellation()
                guard current == request else { return }
                payload = result
                let elapsed = started.duration(to: .now)
                NativeToolTraceLogger.shared.log("chat_code_fence_rendered", ["kind": kind, "blockID": blockID,
                    "sourceBytes": source.utf8.count, "elapsed": String(describing: elapsed),
                    "sourceHash": ChatCodeFenceDocument.digest(Data(source.utf8))])
            } catch is CancellationError { } catch {
                guard !Task.isCancelled, current == request else { return }
                failed = true
                requiresRestart = ChatCodeFenceEngine.shared.requiresRestart
            }
        }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                Group {
                    if showsSource || failed || payload == nil {
                        ScrollView([.horizontal, .vertical]) {
                            Text(source).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true).padding()
                        }
                    } else if let payload {
                        ChatCodeFenceWebView(payload: payload)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .navigationTitle(kind == "mermaid" ? String(localized: "Diagram") : String(localized: "Code comparison"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { expanded = false } }
                    ToolbarItem(placement: .bottomBar) {
                        Toggle(String(localized: "Show code"), isOn: $showsSource).toggleStyle(.button)
                    }
                }
            }
        }
    }

    private var sourcePreview: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(source).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true).padding(8)
        }
        .frame(height: 200)
        .environment(\.layoutDirection, .leftToRight)
    }
}
