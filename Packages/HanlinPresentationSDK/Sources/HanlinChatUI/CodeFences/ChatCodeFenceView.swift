import HanlinLocalization
#if canImport(SwiftUI) && canImport(UIKit) && canImport(WebKit)
import SwiftUI
import HanlinPresentationKit
import UIKit

public struct ChatCodeFenceView: View {
    public let blockID: String
    public let kind: String
    public let source: String
    private let onTrace: HanlinPresentationTraceHandler?

    public init(blockID: String, kind: String, source: String,
                onTrace: HanlinPresentationTraceHandler? = nil) {
        self.blockID = blockID
        self.kind = kind
        self.source = source
        self.onTrace = onTrace
    }
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

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind == "mermaid" ? String(localized: "Diagram", bundle: HanlinLocalization.bundle) : String(localized: "Code comparison", bundle: HanlinLocalization.bundle))
                    .font(HanlinTypography.caption.weight(.semibold))
                Spacer()
                Toggle(String(localized: "Show code", bundle: HanlinLocalization.bundle), isOn: $showsSource).toggleStyle(.button).font(HanlinTypography.caption)
                    .accessibilityIdentifier("hanlin-code-fence-source-toggle-\(blockID)")
                Menu {
                    Button(String(localized: "Copy source", bundle: HanlinLocalization.bundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = source }
                    ShareLink(item: source) { Label(String(localized: "Share source", bundle: HanlinLocalization.bundle), systemImage: "square.and.arrow.up") }
                    Button(String(localized: "Expand", bundle: HanlinLocalization.bundle), systemImage: "arrow.up.left.and.arrow.down.right") { expanded = true }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(String(localized: "Code block actions", bundle: HanlinLocalization.bundle)) }
            }
            if kind == "diff", canSplit {
                Picker(String(localized: "Comparison layout", bundle: HanlinLocalization.bundle), selection: $split) {
                    Text(String(localized: "Unified", bundle: HanlinLocalization.bundle)).tag(false)
                    Text(String(localized: "Side by side", bundle: HanlinLocalization.bundle)).tag(true)
                }.pickerStyle(.segmented)
            }
            if showsSource || failed {
                sourcePreview
            } else if let payload {
                ChatCodeFenceWebView(payload: payload)
                    .frame(height: min(480, max(120, payload.height + 8)))
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                ProgressView(String(localized: "Rendering preview", bundle: HanlinLocalization.bundle))
                    .frame(maxWidth: .infinity, minHeight: 96)
            }
            if failed {
                Text(requiresRestart
                     ? String(localized: "The preview stopped responding. Reopen the app to try again. You can still read or share the source.", bundle: HanlinLocalization.bundle)
                     : String(localized: "Preview is unavailable. The complete source remains available to copy, share or expand.", bundle: HanlinLocalization.bundle))
                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
                if !requiresRestart {
                    Button(String(localized: "Retry preview", bundle: HanlinLocalization.bundle)) { failed = false; retry += 1 }
                        .font(HanlinTypography.caption)
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
                onTrace?("chat_code_fence_rendered", ["kind": kind, "blockID": blockID,
                    "sourceBytes": source.utf8.count, "elapsed": String(describing: elapsed),
                    "sourceHash": ChatCodeFenceDocument.digest(Data(source.utf8))])
            } catch is CancellationError { } catch {
                guard !Task.isCancelled, current == request else { return }
                failed = true
                requiresRestart = ChatCodeFenceEngine.shared.requiresRestart
                // Record the boundary that failed without copying user source,
                // JavaScript exception messages, URLs or rendered markup.
                let failure = error as? ChatCodeFenceEngine.Failure
                let platformError = error as NSError
                onTrace?("chat_code_fence_render_failed", [
                    "kind": current.kind, "blockID": blockID,
                    "failure": failure.map { String(describing: $0) } ?? "platform",
                    "errorDomain": platformError.domain, "errorCode": platformError.code,
                    "requiresRestart": requiresRestart
                ])
            }
        }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                Group {
                    if showsSource || failed || payload == nil {
                        ScrollView([.horizontal, .vertical]) {
                            Text(source).font(HanlinTypography.callout.monospaced()).textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true).padding()
                        }
                    } else if let payload {
                        ChatCodeFenceWebView(payload: payload)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                .navigationTitle(kind == "mermaid" ? String(localized: "Diagram", bundle: HanlinLocalization.bundle) : String(localized: "Code comparison", bundle: HanlinLocalization.bundle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done", bundle: HanlinLocalization.bundle)) { expanded = false } }
                    ToolbarItem(placement: .bottomBar) {
                        Toggle(String(localized: "Show code", bundle: HanlinLocalization.bundle), isOn: $showsSource).toggleStyle(.button)
                    }
                }
            }
        }
    }

    private var sourcePreview: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(source).font(HanlinTypography.callout.monospaced()).textSelection(.enabled)
                .accessibilityIdentifier("hanlin-code-fence-source-text-\(blockID)")
                .fixedSize(horizontal: true, vertical: true).padding(8)
        }
        .frame(height: 200)
        .environment(\.layoutDirection, .leftToRight)
    }
}

#endif
