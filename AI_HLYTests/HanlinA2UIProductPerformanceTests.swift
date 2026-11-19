#if HANLIN_A2UI_POC && canImport(UIKit)
import AISDKProvider
import AISDKProviderUtils
import CryptoKit
import Darwin
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts
import Observation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import AI_Hanlin

/// Native product component measurements, not a substitute renderer or an SLA.
/// Both routes use the original app owner, Session, SwiftData store, presentation,
/// HanlinChatContentView, Markdown renderer and official Surface implementations.
/// Paced source events are deterministic test data, NOT model tokens. ChatView
/// scroll geometry, display FPS, pixel TTFR, signed-device traces and before/after
/// baselines remain separate acceptance obligations.
@MainActor
final class HanlinA2UIProductPerformanceTests: XCTestCase {
    private enum Route: String { case canonicalParts, responsesCompleteBatch }

    // Keep all 36 observations while bounding each XCTest method to six
    // configurations under the unchanged native per-method timeout.
    func testPacedCanonicalPartsOneNodeOriginalMatrix() async throws {
        try await exerciseMatrix(nodes: 1, route: .canonicalParts)
    }

    func testPacedCanonicalPartsTenNodesOriginalMatrix() async throws {
        try await exerciseMatrix(nodes: 10, route: .canonicalParts)
    }

    func testPacedCanonicalPartsHundredNodesOriginalMatrix() async throws {
        try await exerciseMatrix(nodes: 100, route: .canonicalParts)
    }

    func testPacedResponsesOneNodeOriginalMatrix() async throws {
        try await exerciseMatrix(nodes: 1, route: .responsesCompleteBatch)
    }

    func testPacedResponsesTenNodesOriginalMatrix() async throws {
        try await exerciseMatrix(nodes: 10, route: .responsesCompleteBatch)
    }

    func testPacedResponsesHundredNodesOriginalMatrix() async throws {
        try await exerciseMatrix(nodes: 100, route: .responsesCompleteBatch)
    }

    private func exerciseMatrix(nodes: Int, route: Route) async throws {
        for scenario in A2UIBenchmarkScenario.matrix where scenario.nodes == nodes {
            try await exercise(scenario, route: route)
        }
    }

    private func exercise(_ scenario: A2UIBenchmarkScenario, route: Route) async throws {
        let container = try ModelContainer(for: ChatRecords.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let conversation = ChatRecords(name: "Original A2UI benchmark", type: "chat")
        conversation.input = "UNSENT_BENCHMARK_DRAFT"
        context.insert(conversation); try context.save()
        let conversationID = try XCTUnwrap(conversation.id)
        let messageID = UUID(), uiRunID = UUID(), sceneID = UUID()
        let fixture = try A2UIBenchmarkFixture(scenario: scenario, messageID: messageID)
        let pacing = A2UIBenchmarkPacing()
        let owner = HanlinAppAgentSessionOwner()
        // Synchronous authority revocation also covers an assertion/unwrap failure.
        // Normal completion below awaits invalidation before advancing the matrix.
        defer { owner.cancel() }
        let presentation = HanlinA2UIAppPresentation()
        owner.presentation = presentation
        let rendered = A2UIBenchmarkRendered(presentation: presentation, rowID: messageID, uiRunID: uiRunID)
        let host = A2UIBenchmarkHostingController(rootView: A2UIBenchmarkContent(state: rendered))
        let previousWindow = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow),
            "The original native test host must own an attached key window")
        let hostingScene = try XCTUnwrap(previousWindow.windowScene)
        let window = UIWindow(windowScene: hostingScene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow.makeKey() }

        var firstNativeLayout: Double?
        var layoutCallbacks = 0
        host.observedLayout = {
            layoutCallbacks += 1
            guard firstNativeLayout == nil, rendered.appeared,
                  let value = rendered.projection,
                  value.parts.contains(where: { part in
                      guard let surface = value.surface(for: part) else { return false }
                      return surface.surfaceIDs.contains { surface.surface($0)?.componentsModel.components["root"] != nil }
                  }), host.view.bounds.width > 0, host.view.bounds.height > 0 else { return }
            firstNativeLayout = ProcessInfo.processInfo.systemUptime
        }
        defer { host.observedLayout = nil }

        let configuration: HanlinChatModelConfiguration
        let engine: HanlinAISDKAgentEngine
        switch route {
        case .canonicalParts:
            configuration = .init(modelID: "original-canonical-part-fixture",
                endpoint: URL(filePath: "/fixture"), apiKey: "")
            engine = .init(configuration: configuration,
                model: .v3(A2UIPacedCanonicalModel(parts: fixture.canonicalParts,
                    eventsPerSecond: scenario.eventsPerSecond, pacing: pacing)),
                descriptor: .init(kind: .openAICompatible, modelID: configuration.modelID,
                    baseURL: URL(filePath: "/fixture"),
                    structuredPartChannel: HanlinChatStructuredPart.channel))
        case .responsesCompleteBatch:
            configuration = .init(modelID: HanlinNativeStructuredResponse.modelID, company: "OPENAI",
                apiType: "openai-responses", endpoint: "https://api.openai.com/v1/responses",
                credential: "fixture-only-no-network", supportsToolUse: true)
            engine = try .init(configuration: configuration,
                fetch: try fixture.responsesFetch(eventsPerSecond: scenario.eventsPerSecond, pacing: pacing))
        }

        let started = ProcessInfo.processInfo.systemUptime
        let cpuStart = clock()
        var memorySamples = [UInt64]()
        if let sample = Self.physicalFootprint() { memorySamples.append(sample) }
        var delivered = [HanlinChatStructuredPart]()
        var receivedAt = [Double]()
        var firstCanonical: Double?
        var firstSurfaceAdmitted: Double?
        var originalModels = [String: ObjectIdentifier]()
        var lastEvent: HanlinAgentEvent?
        let source = try await owner.stream(request: .init(conversation: conversation,
            conversationID: conversationID, sceneID: sceneID, rowID: messageID, uiRunID: uiRunID,
            temporary: false, interaction: nil), modelContext: context, configuration: configuration,
            engineFactory: { engine }, toolAdapter: nil,
            messages: [.init(role: .user, text: "Show the original benchmark content")], systemPrompt: nil)
        do {
            for try await event in source {
                try owner.receive(event, uiRunID: uiRunID)
                lastEvent = event
                if case .structuredPart(let part) = event.event {
                    if firstCanonical == nil { firstCanonical = ProcessInfo.processInfo.systemUptime }
                    delivered.append(part)
                    receivedAt.append(ProcessInfo.processInfo.systemUptime)
                    if case .textDelta(let text) = part.payload { rendered.text += text }
                    if let projection = rendered.projection {
                        for item in projection.parts {
                            guard let surface = projection.surface(for: item) else { continue }
                            XCTAssertLessThanOrEqual(surface.surfaceIDs.count, 4)
                            for id in surface.surfaceIDs {
                                guard let model = surface.surface(id) else { continue }
                                if let previous = originalModels[id] {
                                    XCTAssertEqual(previous, ObjectIdentifier(model),
                                        "A data update must retain the original official Surface model")
                                } else { originalModels[id] = ObjectIdentifier(model) }
                                if model.componentsModel.components["root"] != nil, firstSurfaceAdmitted == nil {
                                    firstSurfaceAdmitted = ProcessInfo.processInfo.systemUptime
                                }
                            }
                        }
                    }
                    if let sample = Self.physicalFootprint() { memorySamples.append(sample) }
                    // Let the actual SwiftUI/UIKit renderer run; do not force a render/scroll for every event.
                    await Task.yield()
                }
            }
            try owner.producerStreamDrained(uiRunID: uiRunID)
        } catch {
            await owner.invalidate()
            throw error
        }
        let completed = ProcessInfo.processInfo.systemUptime
        let cpuEnd = clock()
        XCTAssertEqual(delivered.map(\.payload), fixture.canonicalParts.map(\.payload))
        XCTAssertEqual(delivered.map(\.sequence), Array(0..<UInt64(fixture.canonicalParts.count)))
        XCTAssertEqual(rendered.text, fixture.markdown)
        XCTAssertEqual(rendered.text.count, scenario.characters)
        XCTAssertEqual(conversation.input, "UNSENT_BENCHMARK_DRAFT")
        let live = try XCTUnwrap(rendered.projection)
        let liveSurfaces = try assertSurfaces(live, scenario: scenario, readOnly: false)
        XCTAssertEqual(Set(liveSurfaces.map(\.key)).count, 5,
            "Five original part owners coexist in one canonical assistant message")
        XCTAssertTrue(liveSurfaces.allSatisfy(\.isReceivingFinished))
        XCTAssertEqual(originalModels.count, 5)

        let pacingResult = await pacing.snapshot()
        XCTAssertEqual(pacingResult.requests, 1)
        XCTAssertEqual(pacingResult.offers.count, fixture.canonicalParts.count)
        let sourceEOF = try XCTUnwrap(pacingResult.completed)
        let firstDelivery = try XCTUnwrap(firstCanonical)
        switch route {
        case .canonicalParts:
            XCTAssertLessThan(firstDelivery, sourceEOF,
                "The existing explicit canonical channel must deliver before source EOF")
        case .responsesCompleteBatch:
            XCTAssertGreaterThanOrEqual(firstDelivery, sourceEOF,
                "The real Responses path must keep complete-batch validation before publication")
        }

        let layoutDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while firstNativeLayout == nil && ContinuousClock.now < layoutDeadline {
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(firstNativeLayout, "Original content must mount and lay out in a real UIWindow")
        XCTAssertGreaterThan(layoutCallbacks, 0)
        XCTAssertTrue(host.view.window === window)
        XCTAssertTrue(window.windowScene === hostingScene)
        XCTAssertFalse(window.isHidden)

        let recordBytes = try XCTUnwrap(conversation.agentSDKRecordData)
        let bindings = owner.bindings
        XCTAssertEqual(bindings.count, 1)
        await owner.invalidate()
        XCTAssertTrue(liveSurfaces.allSatisfy(\.isClosed))
        if let lastEvent {
            XCTAssertThrowsError(try owner.receive(lastEvent, uiRunID: uiRunID),
                "Old native events cannot repopulate an invalidated app owner")
        }
        let replayStarted = ProcessInfo.processInfo.systemUptime
        let restoredOwner = HanlinAppAgentSessionOwner()
        defer { restoredOwner.cancel() }
        let restoredPresentation = HanlinA2UIAppPresentation()
        restoredOwner.presentation = restoredPresentation
        try await restoredOwner.restoreHistory(conversation: conversation, conversationID: conversationID,
            sceneID: sceneID, temporary: false, modelContext: context)
        rendered.presentation = restoredPresentation
        let restored = try XCTUnwrap(rendered.projection)
        _ = try assertSurfaces(restored, scenario: scenario, readOnly: true)
        XCTAssertEqual(restoredOwner.bindings, bindings)
        XCTAssertNil(restoredOwner.session)
        XCTAssertEqual(conversation.agentSDKRecordData, recordBytes)
        XCTAssertEqual(conversation.input, "UNSENT_BENCHMARK_DRAFT")
        let replayPacing = await pacing.snapshot()
        XCTAssertEqual(replayPacing.requests, 1, "Replay must not invoke another provider")
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        await Task.yield()
        let replayEnded = ProcessInfo.processInfo.systemUptime

        #if targetEnvironment(simulator)
        let executionEnvironment = "iOS Simulator"
        #else
        let executionEnvironment = "physical iOS device"
        #endif
        func relative(_ value: Double?) -> Any { value.map { ($0 - started) as Any } ?? NSNull() }
        let offers = pacingResult.offers
        let offerDuration = (offers.last ?? 0) - (offers.first ?? 0)
        let cpuSeconds: Any = cpuStart >= 0 && cpuEnd >= cpuStart
            ? Double(cpuEnd - cpuStart) / Double(CLOCKS_PER_SEC) : NSNull()
        let report: [String: Any] = [
            "schemaVersion": 1, "classification": "OBSERVED_NATIVE_COMPONENT_MEASUREMENTS",
            "route": route.rawValue, "scenario": scenario.name,
            "executionEnvironment": executionEnvironment,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "fixtureSHA256": fixture.digest, "nodesPerSurface": scenario.nodes,
            "simultaneousOriginalPartOwners": 5, "surfacesPerOwner": 1,
            "markdownCharacters": scenario.characters, "dataModelUpdateCount": 50,
            "pacedUnit": route == .canonicalParts ? "canonical part events" : "Responses text delta events",
            "requestedEventsPerSecond": scenario.eventsPerSecond,
            "actualPacedEventCount": offers.count,
            "actualOfferedEventsPerSecond": offerDuration > 0 ? Double(offers.count - 1) / offerDuration : 0,
            "offeredEventSeconds": offers.map { $0 - started },
            "receivedCanonicalPartCount": delivered.count,
            "receivedCanonicalPartSeconds": receivedAt.map { $0 - started },
            "sampleKind": "one observation per configuration in a warm test-host process; no statistical baseline",
            "acceptance": "Consult the actual XCTest result; measurement emission is not a pass certificate",
            "firstCanonicalPartSeconds": relative(firstCanonical),
            "firstSurfaceAdmittedSeconds": relative(firstSurfaceAdmitted),
            "firstHostedNativeLayoutSeconds": relative(firstNativeLayout),
            "sourceEOFSeconds": sourceEOF - started,
            "completeReceiveSeconds": completed - started,
            "replaySeconds": replayEnded - replayStarted,
            "processCPUSeconds": cpuSeconds,
            "sampledPhysicalFootprintMaxBytes": memorySamples.max().map { $0 as Any } ?? NSNull(),
            "physicalFootprintSampleCount": memorySamples.count,
            "memorySampling": "before run and after each canonical part; transient peaks may be missed",
            "layoutCallbackCount": layoutCallbacks,
            "hostWindowWidth": window.bounds.width,
            "hostWindowHeight": window.bounds.height,
            "hostWindowAttachedToOriginalScene": host.view.window === window && window.windowScene === hostingScene,
            "functionalAssertions": "ordered exact payloads, retained models, five owners, EOF, stale rejection, original-store replay and unchanged draft",
            "unmeasured": ["model tokenizer tokens/second", "display FPS", "pixel TTFR",
                "real ChatView scroll request/scrollTo ratio", "instrumented CPU peak", "before/after baseline"],
            "scope": "Original product components in a test UIWindow; in-memory canonical SwiftData store; deterministic provider input. No live-model throughput or full ChatView/device acceptance claim."
        ]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: bytes, as: UTF8.self))
        attachment.name = "A2UI-" + route.rawValue + "-" + scenario.name
        attachment.lifetime = .keepAlways; add(attachment)
        print("HANLIN_A2UI_PRODUCT_BENCHMARK: " +
              String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self))
        if scenario.nodes == 100 && scenario.characters == 50_000 && scenario.eventsPerSecond == 60 {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pixels = XCTAttachment(image: image)
            pixels.name = "A2UI-original-content-replay-" + route.rawValue
            pixels.lifetime = .keepAlways; add(pixels)
        }
        await restoredOwner.invalidate()
    }

    private func assertSurfaces(_ value: HanlinChatContentProjection,
                                scenario: A2UIBenchmarkScenario, readOnly: Bool) throws -> [HanlinA2UIResultProjection] {
        let surfaces = value.parts.compactMap { value.surface(for: $0) }
        XCTAssertEqual(surfaces.count, 5)
        for index in 0..<5 {
            let id = "benchmark-surface-\(index)"
            let projection = try XCTUnwrap(surfaces.first { $0.surfaceIDs == [id] })
            let model = try XCTUnwrap(projection.surface(id))
            XCTAssertEqual(model.componentsModel.components.count, scenario.nodes)
            XCTAssertEqual(model.dataModel.get("/value")?.stringValue, "A2UI_OWNER_\(index)_STEP_9")
            XCTAssertEqual(model.dataModel.get("/payload")?.stringValue, String(repeating: "u", count: 1_024))
            XCTAssertEqual(projection.isReadOnly, readOnly)
            XCTAssertFalse(projection.isClosed)
        }
        return surfaces
    }

    private static func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
    }
}

private struct A2UIBenchmarkScenario: Sendable {
    let nodes: Int
    let characters: Int
    let eventsPerSecond: Int
    var name: String { "nodes\(nodes)-chars\(characters)-events\(eventsPerSecond)-owners5" }
    static let matrix = [1, 10, 100].flatMap { nodes in
        [10_000, 50_000].flatMap { characters in
            [5, 20, 60].map { A2UIBenchmarkScenario(nodes: nodes, characters: characters, eventsPerSecond: $0) }
        }
    }
}

private actor A2UIBenchmarkPacing {
    struct Snapshot: Sendable { let requests: Int; let offers: [Double]; let completed: Double? }
    private var requests = 0
    private var offers = [Double]()
    private var completed: Double?
    func requested() throws {
        requests += 1
        guard requests == 1 else { throw A2UIBenchmarkFailure.unexpectedRequest }
    }
    func offered() { offers.append(ProcessInfo.processInfo.systemUptime) }
    func finish() { completed = ProcessInfo.processInfo.systemUptime }
    func snapshot() -> Snapshot { .init(requests: requests, offers: offers, completed: completed) }
}
private enum A2UIBenchmarkFailure: Error { case unexpectedRequest, fixtureLimit }

private struct A2UIPacedCanonicalModel: LanguageModelV3 {
    let provider = "original-canonical-part-fixture"
    let modelId = "original-canonical-part-fixture"
    let parts: [HanlinChatStructuredPart]
    let eventsPerSecond: Int
    let pacing: A2UIBenchmarkPacing
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        throw HanlinHostError.unsupportedProviderCapability
    }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        try await pacing.requested()
        let content = try parts.map { try $0.providerContent() }
        return .init(stream: AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let clock = ContinuousClock(), start = ContinuousClock.now
                    for (index, item) in content.enumerated() {
                        try await clock.sleep(until: start.advanced(by:
                            .nanoseconds(Int64(index) * 1_000_000_000 / Int64(eventsPerSecond))))
                        try Task.checkCancellation()
                        await pacing.offered()
                        continuation.yield(.custom(item))
                    }
                    await pacing.finish()
                    continuation.yield(.finish(finishReason: .init(unified: .stop),
                        usage: .init(), providerMetadata: nil))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        })
    }
}

private struct A2UIBenchmarkFixture: Sendable {
    let canonicalParts: [HanlinChatStructuredPart]
    let markdown: String
    let wire: String
    var digest: String { SHA256.hash(data: Data(wire.utf8)).map { String(format: "%02x", $0) }.joined() }

    init(scenario: A2UIBenchmarkScenario, messageID: UUID) throws {
        let fence = String(repeating: "\u{0060}", count: 3)
        let header = "Native A2UI benchmark with original mixed content.\n\n"
            + "Inline $E=mc^2$ and a diagram:\n\n" + fence + "mermaid\n"
            + "graph TD\n  A[Input] --> B[Original output]\n" + fence + "\n\n"
        let filler = "This is deterministic original-chat text. "
        let remaining = scenario.characters - header.count
        markdown = header + String(repeating: filler, count: remaining / filler.count)
            + String(repeating: "x", count: remaining % filler.count)
        var payloads = [(String, HanlinChatStructuredPart.Payload)]()
        var wireParts = [[String: Any]]()
        func add(_ key: String, text: String) {
            payloads.append((key, .textDelta(text)))
            wireParts.append(["part": key, "kind": "text", "text": text, "a2uiJSON": NSNull()])
        }
        func frame(_ key: String, body: [String: Any]) throws {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: body,
                options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
            payloads.append((key, .a2uiMessage(protocolVersion: "1.0", json: Data(json.utf8))))
            wireParts.append(["part": key, "kind": "a2ui", "text": NSNull(), "a2uiJSON": json])
        }
        let componentsPerMessage = HanlinA2UIIngress.maximumComponentsPerMessage
        let messagesPerOwner = (scenario.nodes + componentsPerMessage - 1) / componentsPerMessage
        for owner in 0..<5 {
            let id = "benchmark-surface-\(owner)", key = "owner\(owner)"
            try frame(key, body: ["version": "1.0", "createSurface": [
                "surfaceId": id, "catalogId": "https://hanlin.ai/a2ui/catalogs/media/v1"]])
            try frame(key, body: ["version": "1.0", "updateDataModel": [
                "surfaceId": id, "path": "/", "value": ["value": "A2UI_OWNER_\(owner)_INITIAL", "payload": ""]]])
            var components = [[String: Any]]()
            if scenario.nodes == 1 {
                components = [["id": "root", "component": "Text", "text": ["@path": "/value"]]]
            } else {
                var children = [String]()
                var next = 1
                while next < scenario.nodes {
                    let id = "node\(next)"
                    children.append(id)
                    if next + 1 < scenario.nodes {
                        let textID = "node\(next + 1)"
                        components.append(["id": id, "component": "Card", "child": textID])
                        components.append(["id": textID, "component": "Text", "text": ["@path": "/value"]])
                        next += 2
                    } else {
                        components.append(["id": id, "component": "Text", "text": ["@path": "/value"]])
                        next += 1
                    }
                }
                components.insert(["id": "root", "component": "Column", "children": children], at: 0)
            }
            // For a split update, publish referenced children before the root
            // so each batch respects the original ingress limit.
            if messagesPerOwner > 1 { components.reverse() }
            for start in stride(from: 0, to: components.count, by: componentsPerMessage) {
                let end = min(start + componentsPerMessage, components.count)
                try frame(key, body: ["version": "1.0", "updateComponents": [
                    "surfaceId": id, "components": Array(components[start..<end])]])
            }
        }
        let characters = Array(markdown)
        for update in 0..<10 {
            for half in 0..<2 {
                let chunk = update * 2 + half
                let lower = characters.count * chunk / 20, upper = characters.count * (chunk + 1) / 20
                add("markdown_\(chunk)", text: String(characters[lower..<upper]))
                if half == 0 {
                    for owner in 0..<5 {
                        try frame("owner\(owner)", body: ["version": "1.0", "updateDataModel": [
                            "surfaceId": "benchmark-surface-\(owner)", "path": "/",
                            "value": ["value": "A2UI_OWNER_\(owner)_STEP_\(update)",
                                      "payload": String(repeating: "u", count: 1_024)]]])
                    }
                }
            }
        }
        var identities = [String: UUID]()
        canonicalParts = try payloads.enumerated().map { index, item in
            let id = identities[item.0] ?? UUID(); identities[item.0] = id
            return try .init(messageID: messageID, partID: id, sequence: UInt64(index), payload: item.1)
        }
        wire = String(decoding: try JSONSerialization.data(withJSONObject: ["parts": wireParts],
            options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        guard canonicalParts.count == 85 + 5 * (messagesPerOwner - 1), wireParts.count <= 128,
              wire.utf8.count <= 1_048_576, markdown.count == scenario.characters else {
            throw A2UIBenchmarkFailure.fixtureLimit
        }
    }

    func responsesFetch(eventsPerSecond: Int, pacing: A2UIBenchmarkPacing) throws -> FetchFunction {
        func event(_ value: [String: Any]) throws -> Data {
            Data(("data: " + String(decoding: try JSONSerialization.data(withJSONObject: value),
                as: UTF8.self) + "\n\n").utf8)
        }
        let id = "msg_original_a2ui_benchmark"
        let added = try event(["type": "response.output_item.added", "output_index": 0,
            "item": ["id": id, "type": "message", "status": "in_progress", "role": "assistant", "content": []]])
        let characters = Array(wire)
        let chunks = try canonicalParts.indices.map { index in
            let lower = characters.count * index / canonicalParts.count
            let upper = characters.count * (index + 1) / canonicalParts.count
            return try event(["type": "response.output_text.delta", "item_id": id,
                "output_index": 0, "content_index": 0, "delta": String(characters[lower..<upper])])
        }
        let done = try event(["type": "response.output_item.done", "output_index": 0,
            "item": ["id": id, "type": "message", "status": "completed", "role": "assistant",
                "content": [["type": "output_text", "text": wire, "annotations": []]]]])
        // Zero is synthetic fixture usage; it never supplies event pacing or a model-token metric.
        let completed = try event(["type": "response.completed", "response": [
            "id": "resp_original_a2ui_benchmark", "status": "completed",
            "usage": ["input_tokens": 0, "output_tokens": 0]]])
        return { request in
            try await pacing.requested()
            guard request.url?.absoluteString == "https://api.openai.com/v1/responses",
                  request.httpMethod == "POST", let body = request.httpBody,
                  let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  object["model"] as? String == HanlinNativeStructuredResponse.modelID,
                  object["stream"] as? Bool == true,
                  let format = (object["text"] as? [String: Any])?["format"] as? [String: Any],
                  format["type"] as? String == "json_schema", format["strict"] as? Bool == true,
                  format["name"] as? String == "hanlin_chat_parts_v1",
                  let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "text/event-stream"]) else {
                throw A2UIBenchmarkFailure.unexpectedRequest
            }
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let producer = Task {
                    do {
                        continuation.yield(added)
                        let clock = ContinuousClock(), start = ContinuousClock.now
                        for (index, chunk) in chunks.enumerated() {
                            try await clock.sleep(until: start.advanced(by:
                                .nanoseconds(Int64(index) * 1_000_000_000 / Int64(eventsPerSecond))))
                            try Task.checkCancellation()
                            await pacing.offered()
                            continuation.yield(chunk)
                        }
                        await pacing.finish()
                        continuation.yield(done); continuation.yield(completed)
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
                continuation.onTermination = { @Sendable _ in producer.cancel() }
            }
            return FetchResponse(body: .stream(stream), urlResponse: response)
        }
    }
}

@MainActor @Observable
private final class A2UIBenchmarkRendered {
    var presentation: HanlinA2UIAppPresentation
    let rowID: UUID
    let uiRunID: UUID
    var text = ""
    var appeared = false
    init(presentation: HanlinA2UIAppPresentation, rowID: UUID, uiRunID: UUID) {
        self.presentation = presentation; self.rowID = rowID; self.uiRunID = uiRunID
    }
    var projection: HanlinChatContentProjection? {
        presentation.projection(uiRunID: uiRunID, rowID: rowID, text: text)
    }
}
@MainActor
private struct A2UIBenchmarkContent: View {
    let state: A2UIBenchmarkRendered
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if let projection = state.projection {
                    HanlinChatContentView(projection: projection)
                        .onAppear { state.appeared = true }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
@MainActor
private final class A2UIBenchmarkHostingController: UIHostingController<A2UIBenchmarkContent> {
    var observedLayout: (() -> Void)?
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        observedLayout?()
    }
}
#endif
