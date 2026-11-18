import A2UICore
import Foundation
import Observation
import SwiftUI

/// Disposable component UI host: exact production owner/renderer/catalog/media sources,
/// no app database, provider, Session or business Host. Full app acceptance is separate.
@MainActor @Observable
final class MediaReplayFixture: HanlinA2UIResultEventSink {
    let store = HanlinA2UIResultStore()
    let kind: String
    let historical: Bool
    private(set) var projection: HanlinA2UIResultProjection!
    private(set) var outbound = 0
    private(set) var sourceReceipt = "none"
    private(set) var probeReceipt = "not-run"
    private var retainedAction: (() -> Void)?
    var disabled = false
    var visible = true
    private var changedSource = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        kind = args.contains("--gallery") || args.contains("--invalid-gallery") ? "ImageGallery"
            : args.contains("--link") || args.contains("--invalid-link") ? "LinkPreview"
            : args.contains("--audio") ? "AudioPlayer" : args.contains("--video") ? "Video" : "YouTube"
        historical = !args.contains("--live")
        do {
            projection = store.registerModelPart(runID: UUID(), messageID: UUID(), partID: UUID(),
                presentation: historical ? .history : .live, sink: self)
            guard let projection, let file = Bundle.main.url(forResource: "A2UIReplayMedia", withExtension: "jsonl") else {
                throw FixtureError.missing
            }
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            for (index, line) in lines.enumerated() {
                var value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                if kind != "YouTube", var update = value["updateComponents"] as? [String: Any],
                   var components = update["components"] as? [[String: Any]],
                   let offset = components.firstIndex(where: { $0["id"] as? String == "media" }) {
                    if kind == "ImageGallery" {
                        components[offset] = ["id": "media", "component": kind, "items": [
                            ["id": "swiftui", "url": args.contains("--invalid-gallery")
                                ? ("https://127.0.0.1/private.png" as Any) : (["@path": "/source"] as Any),
                             "sourceUrl": ["@path": "/sourcePage"], "title": ["@path": "/sourceTitle"],
                             "description": ["@path": "/sourceDescription"]] as [String: Any],
                            ["id": "swift", "url": "https://developer.apple.com/assets/elements/icons/swift/swift-96x96_2x.png",
                             "sourceUrl": "https://developer.apple.com/swift/", "title": "Swift", "description": "Swift language icon"],
                            ["id": "xcode", "url": "https://developer.apple.com/assets/elements/icons/xcode/xcode-96x96_2x.png",
                             "sourceUrl": "https://developer.apple.com/xcode/", "title": "Xcode", "description": "Xcode development icon"]
                        ]]
                    } else if kind == "LinkPreview" {
                        components[offset] = ["id": "media", "component": kind,
                            "url": args.contains("--invalid-link") ? ("https://user:secret@developer.apple.com/" as Any) : (["@path": "/source"] as Any),
                            "title": "Apple source"]
                    } else {
                        components[offset]["component"] = kind
                    }
                    update["components"] = components
                    value["updateComponents"] = update
                }
                if kind != "YouTube", var update = value["updateDataModel"] as? [String: Any],
                   var model = update["value"] as? [String: Any] {
                    if kind == "ImageGallery" {
                        model["source"] = "https://developer.apple.com/assets/elements/icons/swiftui/swiftui-96x96_2x.png"
                        model["sourcePage"] = "https://developer.apple.com/swiftui/"
                        model["sourceTitle"] = "SwiftUI"
                        model["sourceDescription"] = "SwiftUI framework icon"
                    } else if kind == "LinkPreview" {
                        model["source"] = "https://developer.apple.com/swiftui/"
                    } else {
                        model["source"] = "https://media.example.com/fixture." + (kind == "Video" ? "mp4" : "mp3")
                    }
                    update["value"] = model
                    value["updateDataModel"] = update
                }
                try store.receive(String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self),
                    sequence: UInt64(index), for: projection.key).get()
            }
            if let action = try node("submit").action(for: "action", userActivation: true) {
                retainedAction = { action() }
            } else { throw FixtureError.missing }
            if historical { _ = store.seal(projection.key) }
        } catch { fatalError("Media fixture setup failed: \(error)") }
    }

    enum FixtureError: Error { case missing }
    func receive(_ event: RendererToAgentMessage, for key: HanlinA2UIResultKey) { outbound += 1 }
    func opened(_ url: URL) -> OpenURLAction.Result {
        sourceReceipt = url.absoluteString
        return .handled // Assert the real Link/openURL port without opening another app.
    }
    func probe() async {
        retainedAction?()
        do {
            guard let surface = projection.surface("replay-media") else { throw FixtureError.missing }
            _ = try await surface.callAgentFunction(AgentFunctionCall(
                name: "unavailable", catalogID: HanlinA2UIIngress.mediaCatalogID))
            probeReceipt = "UNEXPECTED_RPC_SUCCESS"
        } catch let error as FunctionError {
            probeReceipt = error.rpcCode
        } catch { probeReceipt = "unexpected-error" }
    }
    func changeSource() {
        guard !historical else { return }
        changedSource.toggle()
        if kind == "ImageGallery" || kind == "LinkPreview" {
            let section = changedSource ? "swift" : "swiftui"
            let value: [String: Any] = ["version": "1.0", "updateDataModel": [
                "surfaceId": "replay-media", "path": "/", "value": [
                    "name": "Ada",
                    "source": kind == "ImageGallery"
                        ? "https://developer.apple.com/assets/elements/icons/\(section)/\(section)-96x96_2x.png"
                        : "https://developer.apple.com/\(section)/",
                    "sourcePage": "https://developer.apple.com/\(section)/",
                    "sourceTitle": changedSource ? "Swift" : "SwiftUI",
                    "sourceDescription": changedSource ? "Updated Swift icon" : "SwiftUI framework icon"
                ]]]
            do {
                try store.receive(String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self),
                    sequence: changedSource ? 3 : 4, for: projection.key).get()
            } catch { probeReceipt = "source-update-failed" }
            return
        }
        let source = kind == "YouTube"
            ? "https://youtu.be/\(changedSource ? "dQw4w9WgXcQ" : "M7lc1UVf-VE")"
            : "https://media.example.com/\(changedSource ? "second" : "fixture").\(kind == "Video" ? "mp4" : "mp3")"
        let value: [String: Any] = ["version": "1.0", "updateDataModel": [
            "surfaceId": "replay-media", "path": "/source", "value": source]]
        do {
            try store.receive(String(decoding: JSONSerialization.data(withJSONObject: value), as: UTF8.self),
                sequence: changedSource ? 3 : 4, for: projection.key).get()
        } catch { probeReceipt = "source-update-failed" }
    }
    func close() { _ = store.discard(projection.key) }
    func seal() { _ = store.seal(projection.key) }
    private func node(_ id: String) throws -> Node {
        guard let root = projection.surface("replay-media")?.rootNode else { throw FixtureError.missing }
        var pending = [root]
        while let node = pending.popLast() {
            if node.id == id { return node }
            pending += node.allChildNodes
        }
        throw FixtureError.missing
    }
}

@main @MainActor
struct MediaReplayUIApp: App {
    @State private var fixture = MediaReplayFixture()
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("outbound:\(fixture.outbound)").accessibilityIdentifier("proof-outbound")
                Text(fixture.probeReceipt).accessibilityIdentifier("proof-probe-result")
                Text(fixture.sourceReceipt).accessibilityIdentifier("proof-source-result")
                HStack {
                    Button("Disable parent") { fixture.disabled.toggle() }.accessibilityIdentifier("proof-disable")
                    Button("Hide media") { fixture.visible.toggle() }.accessibilityIdentifier("proof-hide")
                    Button("Seal owner") { fixture.seal() }.accessibilityIdentifier("proof-seal")
                }
                HStack {
                    Button("Change URL") { fixture.changeSource() }.accessibilityIdentifier("proof-change-source")
                    Button("Close owner") { fixture.close() }.accessibilityIdentifier("proof-close")
                    Button("Probe stale action and RPC") { Task { await fixture.probe() } }.accessibilityIdentifier("proof-probe")
                }
                ScrollView {
                    if fixture.visible, let projection = fixture.projection {
                        HanlinA2UIProjectedResultView(projection: projection)
                            .disabled(fixture.disabled)
                            .environment(\.openURL, OpenURLAction { fixture.opened($0) })
                    }
                }
            }.padding()
        }
    }
}
