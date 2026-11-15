#if HANLIN_A2UI_POC && os(iOS)
import A2UICore
import Foundation
import HanlinPlatformContracts
import SwiftUI
import Testing
import UIKit

@testable import AI_Hanlin

@MainActor
@Suite("A2UI actual iOS host", .serialized)
struct A2UIHostedResultTests {
    private enum WaitFailure: Error { case deadline }

    @MainActor
    private final class Sink: HanlinA2UIResultEventSink {
        var events: [RendererToAgentMessage] = []
        func receive(_ event: RendererToAgentMessage, for key: HanlinA2UIResultKey) { events.append(event) }
    }

    @MainActor
    private final class Host {
        let controller: UIHostingController<AnyView>
        let window: UIWindow
        private weak var previousKeyWindow: UIWindow?
        init(_ view: AnyView) {
            previousKeyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)
            controller = UIHostingController(rootView: view)
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 720, height: 700))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            layout()
        }
        func layout() { controller.view.setNeedsLayout(); controller.view.layoutIfNeeded() }
        func close() {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw WaitFailure.deadline }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func textFields(_ view: UIView) -> [UITextField] {
        let own = (view as? UITextField).map { [$0] } ?? []
        return own + view.subviews.flatMap { textFields($0) }
    }

    private func lines(_ fixture: String) throws -> [String] {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("A2UIFixtures/\(fixture).jsonl")
        let url = FileManager.default.fileExists(atPath: source.path) ? source
            : Bundle.allBundles.compactMap {
                $0.url(forResource: fixture, withExtension: "jsonl", subdirectory: "A2UIFixtures")
                    ?? $0.url(forResource: fixture, withExtension: "jsonl")
            }.first
        let fixtureURL = try #require(url)
        let data = try Data(contentsOf: fixtureURL)
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }

    private func load(_ store: HanlinA2UIResultStore, _ p: HanlinA2UIResultProjection,
                      fixture: String = "form", startingAt: UInt64 = 0) throws {
        for (offset, line) in try lines(fixture).enumerated() {
            try store.receive(line, sequence: startingAt + UInt64(offset), for: p.key).get()
        }
    }

    private func node(_ p: HanlinA2UIResultProjection, id: String) throws -> Node {
        var nodes = [try #require(p.surface("form-a")?.rootNode)]
        while let node = nodes.popLast() {
            if node.id == id { return node }
            nodes.append(contentsOf: node.allChildNodes)
        }
        throw WaitFailure.deadline
    }

    private func item(for p: HanlinA2UIResultProjection) -> AgentTranscriptItem {
        AgentTranscriptItem(id: p.key.resultID, sequence: 0, kind: .userVisibleToolResult,
                            callID: p.key.callID, toolName: "fixture", status: .completed,
                            visibilityAfterCompletion: .remainInChat)
    }

    private func resultView(_ item: AgentTranscriptItem, _ p: HanlinA2UIResultProjection?) -> AnyView {
        AnyView(AgentTranscriptToolResultView(item: item, temporaryRecord: true,
                                             onLaunchRequest: nil, a2uiProjection: p))
    }

    private func bubble(_ item: AgentTranscriptItem, runID: UUID, showsResults: Bool,
                        source: HanlinA2UIResultProjectionSource?) -> AnyView {
        let run = AgentRun(id: runID, groupID: UUID(), status: .completed, transcriptItems: [item])
        return AnyView(ChatBubbleView(
            temporaryRecord: true, containerWidth: 720, id: UUID(), text: "", saveTranlatedText: nil,
            images: nil, imagesText: nil, reasoning: "", reasoningTime: nil,
            isReasoningExpanded: .constant(false), toolContent: "", toolName: "",
            isToolContentExpanded: .constant(false), uploadDocument: nil, documentText: nil,
            resources: nil, prompts: nil, locations: nil, routes: nil, events: nil,
            htmlContent: nil, healthCards: nil, codeBlocks: nil, knowledgeCard: nil,
            agentRun: run, showsAgentActivitySummary: showsResults,
            searchEngine: nil, audioAssets: nil, isVoiceExpanded: .constant(false), showCanvas: false,
            canvas: nil, role: "assistant", model: "fixture", modelCompany: "", modelIdentity: "",
            modelIcon: "", isLastAssistant: false, isLastAssistantGroup: false, splitMarker: false,
            isResponding: false, operationalState: "", operationalDescription: "", onRetry: nil,
            onDelete: nil
        ).environment(\.hanlinA2UIResultProjectionSource, source))
    }

    @Test func projectionSourceRequiresExactRegisteredIdentityAndGeneration() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = Sink()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        let source = try #require(HanlinA2UIResultProjectionSource(store: store, keys: [p.key]))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        for _ in 0..<20 {
            #expect(source.projection(runID: p.key.runID, resultID: p.key.resultID, callID: p.key.callID)?.surface("form-a") === model)
        }
        #expect(source.projection(runID: nil, resultID: p.key.resultID, callID: p.key.callID) == nil)
        #expect(source.projection(runID: UUID(), resultID: p.key.resultID, callID: p.key.callID) == nil)
        #expect(source.projection(runID: p.key.runID, resultID: UUID(), callID: p.key.callID) == nil)
        #expect(source.projection(runID: p.key.runID, resultID: p.key.resultID, callID: nil) == nil)
        #expect(source.projection(runID: p.key.runID, resultID: p.key.resultID, callID: "other") == nil)
        #expect(HanlinA2UIResultProjectionSource(store: store, keys: [p.key, p.key]) == nil)
        let replacement = try #require(store.replace(p.key, callID: p.key.callID, sink: sink))
        #expect(source.projection(runID: p.key.runID, resultID: p.key.resultID, callID: p.key.callID) == nil)
        #expect(HanlinA2UIResultProjectionSource(store: store, keys: [p.key]) == nil)
        #expect(replacement.key.generation != p.key.generation)
    }

    @Test func chatBubblePreservesDisplayGateAndDoesNotInferProjectionFromPayload() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = Sink()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let source = try #require(HanlinA2UIResultProjectionSource(store: store, keys: [p.key]))
        let result = item(for: p) // No persisted embedded payload, handler or renderer kind.
        let host = Host(bubble(result, runID: p.key.runID, showsResults: true, source: source))
        defer { host.close() }
        try await waitUntil { host.layout(); return textFields(host.controller.view).contains { $0.text == "Ada" } }
        // Each negative uses the actual caller path, not a second renderer or a selector mock.
        var nonResult = result
        nonResult.kind = .toolActivity
        var payloadOnly = result
        let wireText = try lines("form").joined(separator: "\n")
        payloadOnly.text = wireText
        payloadOnly.embeddedResultPayload = HanlinEmbeddedResultPayload(
            payload: .string(wireText), metadata: ["renderer": "a2ui"]
        )
        let negatives = [
            bubble(result, runID: p.key.runID, showsResults: false, source: source),
            bubble(result, runID: p.key.runID, showsResults: true, source: nil),
            bubble(result, runID: UUID(), showsResults: true, source: source),
            bubble(nonResult, runID: p.key.runID, showsResults: true, source: source),
            bubble(payloadOnly, runID: p.key.runID, showsResults: true, source: nil)
        ]
        for view in negatives {
            host.controller.rootView = view
            try await waitUntil { host.layout(); return textFields(host.controller.view).isEmpty }
            try await Task.sleep(for: .milliseconds(100))
            #expect(textFields(host.controller.view).isEmpty)
            #expect(!p.isClosed)
        }
    }

    @Test func actualHostInputBindsWithoutReplayAcrossBodyUpdates() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = Sink()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        let identity = try node(p, id: "name").identity
        let result = item(for: p)
        let host = Host(resultView(result, p))
        defer { host.close() }
        try await waitUntil { host.layout(); return textFields(host.controller.view).contains { $0.text == "Ada" } }
        let field = try #require(textFields(host.controller.view).first)
        field.text = "Native edit"
        field.sendActions(for: .editingChanged)
        try await waitUntil { model.dataModel.get("/name")?.stringValue == "Native edit" }
        for _ in 0..<4 { host.controller.rootView = resultView(result, p); host.layout() }
        #expect(p.surface("form-a") === model && !p.isClosed)
        #expect(try node(p, id: "name").identity == identity)
        try load(store, p, fixture: "update", startingAt: 3)
        try await waitUntil { host.layout(); return textFields(host.controller.view).contains { $0.text == "Grace" } }
        #expect(try node(p, id: "name").identity == identity)
    }

    @Test func sealedHostRetainsVisibleModelAndDisablesNativeInput() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = Sink()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        let host = Host(resultView(item(for: p), p))
        defer { host.close() }
        try await waitUntil { host.layout(); return textFields(host.controller.view).contains { $0.text == "Ada" } }
        let action = try #require(try node(p, id: "submit").action(for: "action", userActivation: true))
        action()
        store.sealRun(p.key.runID)
        action()
        try await waitUntil {
            host.layout()
            return textFields(host.controller.view).contains { $0.text == "Ada" && !$0.isEnabled }
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(p.surface("form-a") === model && p.isReadOnly && !p.isClosed && sink.events.isEmpty)
    }

    @Test func presentedProjectionDismissalAndHostRemovalDoNotDiscardOwner() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = Sink()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        let host = Host(resultView(item(for: p), p))
        defer { host.close() }
        try await waitUntil { host.layout(); return !textFields(host.controller.view).isEmpty }
        // Actual UIKit presentation of the same owned renderer. This does not exercise the
        // host's expansion-button activation; that remains a separate app UI acceptance check.
        let expanded = UIHostingController(rootView: HanlinA2UIProjectedResultView(projection: p))
        host.controller.present(expanded, animated: false)
        try await waitUntil { expanded.view.window != nil }
        #expect(p.surface("form-a") === model && !p.isClosed)
        expanded.dismiss(animated: false)
        try await waitUntil { host.controller.presentedViewController == nil }
        #expect(p.surface("form-a") === model && !p.isClosed)
        host.close()
        #expect(store.projection(for: p.key)?.surface("form-a") === model)
        #expect(store.discard(p.key) && p.isClosed && !store.discard(p.key))
    }

    @Test func nilAndMismatchedProjectionKeepExistingNativeFallbacks() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = Sink()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        for renderer in [ToolResultRendererKind.modernNative, .legacyExisting] {
            var fallback = item(for: p)
            fallback.id = UUID()
            fallback.resultRendererKind = renderer
            fallback.nativeUIBlocks = [NativeUIBlock(type: .text, title: "Fallback", body: "Existing native content")]
            for projection in [nil, p] as [HanlinA2UIResultProjection?] {
                let host = Host(resultView(fallback, projection))
                defer { host.close() }
                try await waitUntil {
                    host.layout()
                    let size = host.controller.sizeThatFits(in: CGSize(width: 720, height: 1_000))
                    return size.height.isFinite && size.height > 0
                }
                #expect(textFields(host.controller.view).isEmpty)
                #expect(!p.isClosed)
            }
        }
    }
}
#endif
