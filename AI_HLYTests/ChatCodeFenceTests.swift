import Foundation
import SwiftUI
import Testing
import UIKit
import WebKit
#if canImport(HanlinCodeFenceProof)
@testable import HanlinCodeFenceProof
#else
@testable import AI_Hanlin
#endif

@MainActor
@Suite("Pinned local code-fence rendering", .serialized)
struct ChatCodeFenceTests {
    @Test func actualWebKitRendersRequiredMermaidFamiliesAndCachesExactInputs() async throws {
        let engine = ChatCodeFenceEngine()
        let fixtures = [
            "flowchart LR\nA[\"שלום🙂\"] --> B[\"OAuth\"]",
            "sequenceDiagram\nparticipant U as משתמש\nparticipant S as Server\nU->>S: OAuth2 request\nS-->>U: response",
            "stateDiagram-v2\n[*] --> Pending\nPending --> Paid: approve\nPaid --> [*]",
            "classDiagram\nclass Order {\n+String id\n+submit()\n}\nOrder --> Customer",
            "erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\nstring name\n}",
            "gantt\ntitle Release\ndateFormat YYYY-MM-DD\nsection Work\nBuild :2026-11-12, 2d\nTest :2026-11-14, 1d",
            "pie title Status\n\"Done\" : 60\n\"Open\" : 40"
        ]
        for source in fixtures {
            let first = try await engine.render(kind: "mermaid", source: source, dark: false, fontSize: 17, split: false)
            #expect(first.html.contains("<svg") && first.width > 0 && first.height > 0)
            #expect(!first.html.contains("<script"))
            let cached = try await engine.render(kind: "mermaid", source: source, dark: false, fontSize: 17, split: false)
            #expect(first.id == cached.id && first.html == cached.html)
        }
        let dark = try await engine.render(kind: "mermaid", source: fixtures[0], dark: true, fontSize: 22, split: false)
        #expect(dark.dark && dark.fontSize == 22 && dark.html.contains("שלום"))
    }

    @Test func actualWebKitParsesFullUnifiedAndSplitDiffWithoutExecutingSource() async throws {
        let engine = ChatCodeFenceEngine()
        let source = "--- a/auth.ts\n+++ b/auth.ts\n@@ -1 +1 @@\n-old(\"שלום\")\n+updated(\"שלום🙂\")\n"
        for split in [false, true] {
            let result = try await engine.render(kind: "diff", source: source, dark: false, fontSize: 16, split: split)
            #expect(result.html.contains("d2h-ins") && result.html.contains("d2h-del"))
            #expect(result.html.contains("auth.ts"))
            #expect(!result.html.contains("<script"))
        }
        let lines = (0..<1_000).map { "-before\($0)\n+after\($0) שלום" }.joined(separator: "\n")
        let large = "--- a/large.txt\n+++ b/large.txt\n@@ -1,1000 +1,1000 @@\n\(lines)\n"
        let result = try await engine.render(kind: "diff", source: large, dark: true, fontSize: 16, split: false)
        #expect(result.html.contains("after999") && result.html.contains("before999"))
        #expect(result.height > 0)
        await #expect(throws: (any Error).self) {
            _ = try await engine.render(kind: "diff", source: "not a diff", dark: false, fontSize: 16, split: false)
        }
    }

    @Test func assetsFailClosedOnTamperingAndVisibleDocumentDisablesScripts() async throws {
        let assets = try ChatCodeFenceDocument.loadAssets()
        let worker = ChatCodeFenceDocument.workerHTML(assets: assets)
        #expect(worker.contains("connect-src 'none'") && worker.contains("frame-src 'none'"))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("tampered".utf8).write(to: root.appending(path: "HanlinCodeFenceRenderer.js"))
        let manifest: [String: Any] = ["schemaVersion": 1, "files": [["name": "HanlinCodeFenceRenderer.js", "bytes": assets.script.utf8.count,
            "sha256": ChatCodeFenceDocument.digest(Data(assets.script.utf8))]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appending(path: "HanlinCodeFenceAssets.json"))
        #expect(throws: (any Error).self) { _ = try ChatCodeFenceDocument.loadAssets(directory: root) }

        let payload = ChatCodeFencePayload(html: "<svg viewBox='0 0 10 10'></svg>", css: assets.css, width: 10, height: 10, fontSize: 16, dark: false)
        let html = ChatCodeFenceDocument.readonlyHTML(payload)
        #expect(html.contains("script-src 'none'") && html.contains("base-uri 'none'") && html.contains("dir=\"ltr\""))
        let host = UIHostingController(rootView: ChatCodeFenceWebView(payload: payload))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let view = try #require(findWebView(host.view))
        #expect(!view.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(!view.configuration.websiteDataStore.isPersistent)
        #expect(!view.allowsLinkPreview)
    }

    @Test func cancellationRejectsAnOfflinePreviewWithoutReturningStaleContent() async throws {
        let engine = ChatCodeFenceEngine()
        let work = Task {
            try await engine.render(kind: "mermaid", source: "flowchart LR\nA-->B", dark: false, fontSize: 16, split: false)
        }
        work.cancel()
        await #expect(throws: CancellationError.self) { _ = try await work.value }
    }

    private func findWebView(_ view: UIView) -> WKWebView? {
        if let view = view as? WKWebView { return view }
        for child in view.subviews { if let found = findWebView(child) { return found } }
        return nil
    }
}
