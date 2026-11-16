import Foundation

#if !HANLIN_A2UI_PORTABLE_RUNNER
import Testing
@testable import AI_Hanlin
#endif

private struct A2UICheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func requireA2UI(_ condition: Bool, _ message: String) throws {
    guard condition else { throw A2UICheckFailure(description: message) }
}

private let diagnosticCanary = "HANLIN_PRIVATE_CANARY_7D2F"

private func requireNoDiagnosticCanary(_ rejection: HanlinA2UIIngress.Rejection) throws {
    let fields = [rejection.failure.rawValue, rejection.surfaceID ?? "", rejection.sdkErrorType ?? ""]
        + rejection.diagnostics.map(\.code)
    let renderings = fields + [String(describing: rejection), String(reflecting: rejection),
                               rejection.localizedDescription]
        + rejection.diagnostics.map { String(reflecting: $0) }
    let leaked = renderings.contains { $0.contains(diagnosticCanary) }
    try requireA2UI(!leaked, "Private canary escaped a surfaced diagnostic field/rendering")
}

private enum A2UIFixture {
    static func data(_ name: String, extension ext: String = "jsonl") throws -> Data {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("A2UIFixtures").appendingPathComponent("\(name).\(ext)")
        if FileManager.default.fileExists(atPath: source.path) {
            return try Data(contentsOf: source)
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "A2UIFixtures")
                ?? bundle.url(forResource: name, withExtension: ext) {
                return try Data(contentsOf: url)
            }
        }
        throw A2UICheckFailure(description: "Missing fixture \(name).\(ext); fixture staging is required")
    }

    static func lines(_ name: String) throws -> [String] {
        String(decoding: try data(name), as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }
}

private enum A2UIUncorrelatedInputs {
    static func messages() throws -> [String] {
        let ids: [String?] = [nil, "", "  ", String(repeating: "x", count: 129), String(repeating: "x", count: 60_000),
                             String(repeating: "א", count: 65), "form-foreign", "form-a", "form-b"]
        return try ["unknownOperation", "callRendererFunction", "agentFunctionResponse"].flatMap { operation in
            try ids.map { id in
                var payload: [String: Any] = [:]
                if let id { payload["surfaceId"] = id }
                let data = try JSONSerialization.data(withJSONObject: ["version": "1.0", operation: payload])
                return String(decoding: data, as: UTF8.self)
            }
        }
    }
}

/// These checks intentionally stop at framing. They do not emulate SDK schema or renderer behavior.
private enum A2UIPortableChecks {
    static let scenarios: [(String, @Sendable () throws -> Void)] = [
        ("acceptsOfficialV1FixtureFrames", acceptsOfficialV1FixtureFrames),
        ("rejectsMalformedAndAmbiguousFrames", rejectsMalformedAndAmbiguousFrames),
        ("rejectsOtherProtocolVersions", rejectsOtherProtocolVersions),
        ("preservesUnicodeSurfaceIdentity", preservesUnicodeSurfaceIdentity),
        ("boundsUTF8MessageAndComponentBatch", boundsUTF8MessageAndComponentBatch),
        ("rejectsRPCAndUnnegotiatedCatalogs", rejectsRPCAndUnnegotiatedCatalogs),
        ("rejectedEnvelopesNeverExportSurfaceCorrelation", rejectedEnvelopesNeverExportSurfaceCorrelation),
        ("componentValidationRemainsWithSDK", componentValidationRemainsWithSDK)
    ]

    private static func inspect(_ json: String) throws -> HanlinA2UIIngress.Frame {
        try HanlinA2UIIngress.inspect(Data(json.utf8))
    }

    private static func rejection(_ json: String, is expected: HanlinA2UIIngress.Failure) throws {
        do {
            _ = try inspect(json)
            throw A2UICheckFailure(description: "Accepted rejected input; expected \(expected)")
        } catch let error as HanlinA2UIIngress.Rejection {
            try requireA2UI(error.failure == expected, "Expected \(expected), got \(error)")
        }
    }

    static func acceptsOfficialV1FixtureFrames() throws {
        for name in ["form", "update", "rtl", "unknown", "unknown-function", "invalid-components"] {
            let lines = try A2UIFixture.lines(name)
            try requireA2UI(!lines.isEmpty, "Empty fixture \(name)")
            for line in lines { _ = try inspect(line) }
        }
        let form = try A2UIFixture.lines("form").map(inspect)
        try requireA2UI(form.map(\.operation) == [.createSurface, .updateDataModel, .updateComponents],
                       "Form fixture lifecycle changed")
        try requireA2UI(Set(form.map(\.surfaceID)) == ["form-a"], "Form route changed")
    }

    static func rejectsMalformedAndAmbiguousFrames() throws {
        for json in ["[]", "null", "{}", "{\"messages\":[]}",
                     #"{"version":"1.0","deleteSurface":{"surfaceId":"s"},"updateDataModel":{"surfaceId":"s"}}"#,
                     #"{"version":"1.0","deleteSurface":{"surfaceId":"s"},"extra":{}}"#,
                     String(decoding: try A2UIFixture.data("malformed", extension: "txt"), as: UTF8.self)] {
            try rejection(json, is: .malformedEnvelope)
        }
        do {
            _ = try HanlinA2UIIngress.inspect(Data([0xFF, 0xFE]))
            throw A2UICheckFailure(description: "Accepted invalid UTF-8")
        } catch let error as HanlinA2UIIngress.Rejection {
            try requireA2UI(error.failure == .malformedEnvelope, "Invalid UTF-8 classification")
        }
    }

    static func rejectsOtherProtocolVersions() throws {
        for version in [#""v0.9.1""#, #""0.8""#, "1", "true"] {
            try rejection("{\"version\":\(version),\"deleteSurface\":{\"surfaceId\":\"s\"}}",
                          is: .unsupportedVersion)
        }
    }

    static func preservesUnicodeSurfaceIdentity() throws {
        let id = "תוצאה/א"
        let frame = try inspect("{\"version\":\"1.0\",\"deleteSurface\":{\"surfaceId\":\"\(id)\"}}")
        try requireA2UI(frame.surfaceID == id, "Unicode surface ID was rewritten")
        for id in ["", "  ", String(repeating: "א", count: 65)] {
            try rejection("{\"version\":\"1.0\",\"deleteSurface\":{\"surfaceId\":\"\(id)\"}}",
                          is: .invalidSurfaceID)
        }
    }

    static func boundsUTF8MessageAndComponentBatch() throws {
        let prefix = #"{"version":"1.0","updateDataModel":{"surfaceId":"s","path":"/x","value":""#
        let suffix = #""}}"#
        let budget = HanlinA2UIIngress.maximumMessageBytes - prefix.utf8.count - suffix.utf8.count
        _ = try inspect(prefix + String(repeating: "a", count: budget) + suffix)
        try rejection(prefix + String(repeating: "א", count: budget) + suffix, is: .messageTooLarge)
        let component = #"{"id":"root","component":"Text","text":"x"}"#
        let components = Array(repeating: component, count: 65).joined(separator: ",")
        try rejection("{\"version\":\"1.0\",\"updateComponents\":{\"surfaceId\":\"s\",\"components\":[\(components)]}}",
                      is: .tooManyComponents)
    }

    static func rejectsRPCAndUnnegotiatedCatalogs() throws {
        try rejection(#"{"version":"1.0","callRendererFunction":{"surfaceId":"s"}}"#,
                      is: .unsupportedOperation)
        try rejection(#"{"version":"1.0","agentFunctionResponse":{"functionCallId":"unsolicited","value":"x"}}"#,
                      is: .unsupportedOperation)
        try rejection(#"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"https://untrusted.invalid/catalog"}}"#,
                      is: .unsupportedCatalog)
        try rejection(#"{"version":"1.0","createSurface":{"surfaceId":"s"}}"#,
                      is: .unsupportedCatalog)
    }

    static func componentValidationRemainsWithSDK() throws {
        // A transport check must not claim that component schemas passed.
        for line in try A2UIFixture.lines("invalid-components") + A2UIFixture.lines("unknown") {
            let frame = try inspect(line)
            try requireA2UI(frame.operation == .updateComponents, "Invalid-component fixture route")
        }
        let rejection = HanlinA2UIIngress.Rejection(
            .sdkValidation, surfaceID: "form-a", sdkErrorType: diagnosticCanary + ".A2UIValidationError",
            diagnostics: [.init(code: diagnosticCanary), .init(code: "invalid_identifier")]
        )
        try requireNoDiagnosticCanary(rejection)
        try requireA2UI(rejection.diagnostics.map(\.code) == ["SDK_ERROR", "invalid_identifier"],
                       "Diagnostic code allowlist lost stable failure classification")
        try requireA2UI(rejection.sdkErrorType == "A2UIError", "Unknown error type was retained")
        let known = HanlinA2UIIngress.Rejection(.sdkValidation, sdkErrorType: "A2UICore.A2UIValidationError")
        try requireA2UI(known.sdkErrorType == "A2UIValidationError", "Stable SDK error type was lost")
    }

    static func rejectedEnvelopesNeverExportSurfaceCorrelation() throws {
        for message in try A2UIUncorrelatedInputs.messages() {
            do {
                _ = try inspect(message)
                throw A2UICheckFailure(description: "Unsupported operation was accepted")
            } catch let error as HanlinA2UIIngress.Rejection {
                try requireA2UI(error.failure == .unsupportedOperation, "Unsupported classification changed")
                try requireA2UI(error.surfaceID == nil, "Raw unsupported-operation ID escaped rejection")
                try requireA2UI(error.sdkErrorType == nil && error.diagnostics.isEmpty,
                               "Ingress rejection falsely acquired SDK diagnostics")
            }
        }
        for message in [
            #"{"version":"0.8","deleteSurface":{"surfaceId":"form-a"}}"#,
            #"{"version":"1.0","createSurface":{"surfaceId":"form-a","catalogId":"foreign"}}"#
        ] {
            do {
                _ = try inspect(message)
                throw A2UICheckFailure(description: "Invalid protocol/catalog was accepted")
            } catch let error as HanlinA2UIIngress.Rejection {
                try requireA2UI(error.surfaceID == nil, "Rejected envelope acquired target correlation")
            }
        }
    }
}

private enum A2UIWaitError: Error { case deadline, ended }

/// A callback drives progress; the clock only bounds a missing callback. No yield/poll assumption.
private func nextA2UIValue<Element: Sendable>(
    _ stream: AsyncStream<Element>, timeout: Duration = .seconds(2)
) async throws -> Element {
    try await withThrowingTaskGroup(of: Element.self) { group in
        defer { group.cancelAll() }
        group.addTask {
            for await value in stream { return value }
            throw A2UIWaitError.ended
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw A2UIWaitError.deadline
        }
        guard let value = try await group.next() else { throw A2UIWaitError.ended }
        return value
    }
}

/// Negative observation must not await/cancel an iterator on a stream needed later.
/// Recorder counts are monotonic; check before and after yielding to queued SDK callbacks.
private func requireA2UIQuiet(
    expectedCount: Int, duration: Duration = .milliseconds(100),
    count: @Sendable () -> Int, failureMessage: String
) async throws {
    try requireA2UI(count() == expectedCount, failureMessage)
    try await Task.sleep(for: duration)
    try requireA2UI(count() == expectedCount, failureMessage)
}

#if HANLIN_A2UI_PORTABLE_RUNNER
@main
private enum A2UIPortableRunner {
    static func main() throws {
        for (name, scenario) in A2UIPortableChecks.scenarios {
            try scenario()
            print("EXECUTED_PASS \(name)")
        }
        print("Portable framing: \(A2UIPortableChecks.scenarios.count) passed. SDK/SwiftUI cases: NOT_RUN.")
    }
}
#else
@Suite("A2UI portable ingress")
struct A2UIIngressTests {
    @Test func acceptsOfficialV1FixtureFrames() throws { try A2UIPortableChecks.acceptsOfficialV1FixtureFrames() }
    @Test func rejectsMalformedAndAmbiguousFrames() throws { try A2UIPortableChecks.rejectsMalformedAndAmbiguousFrames() }
    @Test func rejectsOtherProtocolVersions() throws { try A2UIPortableChecks.rejectsOtherProtocolVersions() }
    @Test func preservesUnicodeSurfaceIdentity() throws { try A2UIPortableChecks.preservesUnicodeSurfaceIdentity() }
    @Test func boundsUTF8MessageAndComponentBatch() throws { try A2UIPortableChecks.boundsUTF8MessageAndComponentBatch() }
    @Test func rejectsRPCAndUnnegotiatedCatalogs() throws { try A2UIPortableChecks.rejectsRPCAndUnnegotiatedCatalogs() }
    @Test func rejectedEnvelopesNeverExportSurfaceCorrelation() throws { try A2UIPortableChecks.rejectedEnvelopesNeverExportSurfaceCorrelation() }
    @Test func componentValidationRemainsWithSDK() throws { try A2UIPortableChecks.componentValidationRemainsWithSDK() }
}

#if HANLIN_A2UI_POC
import A2UICore
import A2UISwiftUI
import BasicCatalog
import BasicCatalogSwiftUI
import SwiftUI
import Synchronization

private final class A2UIEventRecorder: Sendable {
    let events = Mutex<[RendererToAgentMessage]>([])
    let stream: AsyncStream<RendererToAgentMessage>
    private let continuation: AsyncStream<RendererToAgentMessage>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
    }

    func record(_ event: RendererToAgentMessage) {
        events.withLock { $0.append(event) }
        continuation.yield(event)
    }
    var snapshot: [RendererToAgentMessage] { events.withLock { $0 } }
    func requireQuiet(expectedCount: Int, failureMessage: String) async throws {
        try await requireA2UIQuiet(expectedCount: expectedCount,
                                  count: { self.snapshot.count }, failureMessage: failureMessage)
    }
    deinit { continuation.finish() }
}

@MainActor
private final class A2UIResultSinkRecorder: HanlinA2UIResultEventSink {
    let recorder: A2UIEventRecorder
    private(set) var keys: [HanlinA2UIResultKey] = []
    init(recorder: A2UIEventRecorder = A2UIEventRecorder()) { self.recorder = recorder }
    func receive(_ event: RendererToAgentMessage, for key: HanlinA2UIResultKey) {
        keys.append(key)
        recorder.record(event)
    }
}

@MainActor
@Suite("A2UI official exact-pin SDK")
struct A2UISDKTests {
    @Test func customMediaCatalogResolvesYouTubeThroughOfficialGraphAndBinding() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        defer { session.close() }
        try session.receive("""
        {"version":"1.0","createSurface":{"surfaceId":"youtube","catalogId":"https://hanlin.ai/a2ui/catalogs/media/v1"}}
        """).get()
        try session.receive("""
        {"version":"1.0","updateDataModel":{"surfaceId":"youtube","path":"/","value":{"video":"https://youtu.be/M7lc1UVf-VE"}}}
        """).get()
        try session.receive("""
        {"version":"1.0","updateComponents":{"surfaceId":"youtube","components":[{"id":"root","component":"YouTube","url":{"@path":"/video"}}]}}
        """).get()
        let root = try #require(session.surface("youtube")?.rootNode)
        #expect(root.string(for: "url") == "https://youtu.be/M7lc1UVf-VE")
        let identity = root.identity
        try session.receive("""
        {"version":"1.0","updateDataModel":{"surfaceId":"youtube","path":"/video","value":"https://www.youtube.com/shorts/M7lc1UVf-VE"}}
        """).get()
        #expect(root.identity == identity)
        #expect(root.string(for: "url") == "https://www.youtube.com/shorts/M7lc1UVf-VE")
        #expect(HanlinMediaCatalog.makeCatalog().components.count == 19)
    }

    @Test func customMediaCannotAlterOfficialCatalogOrAdmitScriptFields() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        defer { session.close() }
        try session.receive("""
        {"version":"1.0","createSurface":{"surfaceId":"official","catalogId":"https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"}}
        """).get()
        let wrongCatalog = session.receive("""
        {"version":"1.0","updateComponents":{"surfaceId":"official","components":[{"id":"root","component":"YouTube","url":"https://youtu.be/M7lc1UVf-VE"}]}}
        """)
        if case .success = wrongCatalog { Issue.record("Official catalog admitted a Hanlin extension") }
        try session.receive("""
        {"version":"1.0","createSurface":{"surfaceId":"media","catalogId":"https://hanlin.ai/a2ui/catalogs/media/v1"}}
        """).get()
        let script = session.receive("""
        {"version":"1.0","updateComponents":{"surfaceId":"media","components":[{"id":"root","component":"YouTube","url":"https://youtu.be/M7lc1UVf-VE","javascript":"model supplied script"}]}}
        """)
        if case .success = script { Issue.record("Unknown script property was accepted") }
        #expect(BasicCatalog.makeCatalog(version: .v10).components["YouTube"] == nil)
    }

    @Test func successfulProducerEOFKeepsOriginalModelActionAndClosesInput() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let run = UUID(), message = UUID(), part = UUID()
        let p = try #require(store.registerModelPart(runID: run, messageID: message, partID: part, sink: sink))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        let identity = try node(p, id: "name").identity
        store.finishRun(run)
        store.finishRun(run)
        #expect(p.isReceivingFinished && !p.isReadOnly && !p.isClosed)
        let retainedIdentity = try node(p, id: "name").identity
        #expect(p.surface("form-a") === model && retainedIdentity == identity)
        #expect(admissionFailure(store.receive(try #require(A2UIFixture.lines("update").first), sequence: 3, for: p.key)) == .inputFinished)
        #expect(store.registerModelPart(runID: run, messageID: message, partID: UUID(), sink: sink) == nil)
        #expect(store.register(runID: run, resultID: UUID(), callID: "late", sink: sink) == nil)
        A2UITextField(node: try node(p, id: "name")).valueBinding.wrappedValue = "After EOF"
        let action = try #require(try node(p, id: "submit").action(for: "action", userActivation: true))
        action()
        let event = try await nextA2UIValue(sink.recorder.stream)
        guard case .action(let resolved) = event else { Issue.record("Expected actual SDK action"); return }
        #expect(resolved.context["name"]?.stringValue == "After EOF")
        #expect(sink.keys == [p.key] && p.key.origin == .model(messageID: message) && p.key.callID == nil)
    }

    @Test func producerEOFDoesNotSurviveRevocationOrFollowAnotherGeneration() async throws {
        for discard in [false, true] {
            let store = HanlinA2UIResultStore()
            defer { store.discardAll() }
            let sink = A2UIResultSinkRecorder()
            let p = try #require(store.registerModelPart(runID: UUID(), messageID: UUID(), partID: UUID(), sink: sink))
            try load(store, p)
            store.finishRun(p.key.runID)
            let action = try #require(try node(p, id: "submit").action(for: "action", userActivation: true))
            action()
            if discard { store.discardAll() } else { store.sealRun(p.key.runID) }
            store.finishRun(p.key.runID) // EOF never removes prior terminal revocation.
            action()
            try await sink.recorder.requireQuiet(expectedCount: 0, failureMessage: "Revoked completed owner delivered action")
            #expect(p.isReadOnly && p.isClosed == discard)
            #expect(store.registerModelPart(runID: p.key.runID, messageID: UUID(), partID: p.key.resultID, sink: sink) == nil)
        }
    }

    @Test func producerEOFCancelsOnlyItsReceiverAndCannotReplaceFinishedTool() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let a = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "a", sink: sink))
        let b = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "b", sink: sink))
        try load(store, a)
        let state = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(4))
        let receiver = Task { @MainActor in
            defer { state.continuation.finish() }
            state.continuation.yield("started")
            do { try await Task.sleep(for: .seconds(30)); state.continuation.yield("unexpected timeout") }
            catch { state.continuation.yield(Task.isCancelled ? "cancelled" : "unexpected error") }
        }
        #expect(store.attachReceiveTask(receiver, for: a.key))
        #expect(try await nextA2UIValue(state.stream) == "started")
        store.finishRun(a.key.runID)
        #expect(try await nextA2UIValue(state.stream) == "cancelled")
        #expect(store.replace(a.key, callID: "replaced", sink: sink) == nil)
        let rejected = Task { @MainActor in }
        #expect(!store.attachReceiveTask(rejected, for: a.key) && rejected.isCancelled)
        try load(store, b)
        #expect(!b.isReceivingFinished && !b.isReadOnly)
        #expect(store.register(runID: b.key.runID, resultID: UUID(), callID: "still-active", sink: sink) != nil)
    }

    @Test func modelPartUsesMessageIdentityWithoutToolCall() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let run = UUID(), message = UUID(), part = UUID()
        let p = try #require(store.registerModelPart(runID: run, messageID: message, partID: part, sink: sink))
        #expect(p.key.callID == nil)
        #expect(p.key.origin == .model(messageID: message))
        let fabricatedToolWasRejected = store.register(runID: run, resultID: part, callID: "invented-tool", sink: sink) == nil
        #expect(fabricatedToolWasRejected) // Keep a failing diagnostic out of the cyclic owner graph.
        #expect(store.replace(p.key, callID: "invented-tool", sink: sink) == nil)
        #expect(HanlinA2UIResultProjectionSource(store: store, keys: [p.key]) == nil)
        try load(store, p)
        #expect(try node(p, id: "greeting").string(for: "text") == "Ada")
    }

    @Test func orderedModelProjectionPreservesTextAndRegisteredSurface() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let run = UUID(), message = UUID(), part = UUID()
        let p = try #require(store.registerModelPart(runID: run, messageID: message, partID: part, sink: sink))
        try load(store, p)
        let parts: [HanlinChatContentProjection.Part] = [
            .init(id: UUID(), content: .markdown("שלום\n\n")),
            .init(id: part, content: .surface(p.key)),
            .init(id: UUID(), content: .markdown("**Summary**"))
        ]
        let projection = try #require(HanlinChatContentProjection(runID: run, messageID: message, parts: parts, store: store))
        let source = try #require(HanlinChatContentProjectionSource(messages: [projection]))
        #expect(projection.parts.map(\.id) == parts.map(\.id))
        #expect(source.projection(runID: run, messageID: message, text: "שלום\n\n**Summary**") === projection)
        #expect(source.projection(runID: run, messageID: message, text: "text cannot disappear") == nil)
        #expect(source.projection(runID: UUID(), messageID: message, text: projection.plainText) == nil)
        #expect(source.projection(runID: run, messageID: UUID(), text: projection.plainText) == nil)
        let model = try #require(p.surface("form-a"))
        for _ in 0..<10 { #expect(projection.surface(for: parts[1])?.surface("form-a") === model) }
        A2UITextField(node: try node(p, id: "name")).valueBinding.wrappedValue = "Local edit"
        #expect(try node(p, id: "greeting").string(for: "text") == "Local edit")
        #expect(projection.surface(for: parts[0]) == nil)
    }

    @Test func modelProjectionRejectsForeignIdentityAndAmbiguousParts() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let run = UUID(), message = UUID(), part = UUID()
        let p = try #require(store.registerModelPart(runID: run, messageID: message, partID: part, sink: sink))
        let surface = HanlinChatContentProjection.Part(id: part, content: .surface(p.key))
        #expect(HanlinChatContentProjection(runID: UUID(), messageID: message, parts: [surface], store: store) == nil)
        #expect(HanlinChatContentProjection(runID: run, messageID: UUID(), parts: [surface], store: store) == nil)
        #expect(HanlinChatContentProjection(runID: run, messageID: message, parts: [surface, surface], store: store) == nil)
        #expect(HanlinChatContentProjection(runID: run, messageID: message,
            parts: [.init(id: UUID(), content: .surface(p.key))], store: store) == nil)
        let tool = try #require(store.register(runID: run, resultID: UUID(), callID: "actual-call", sink: sink))
        #expect(HanlinChatContentProjection(runID: run, messageID: message,
            parts: [.init(id: tool.key.resultID, content: .surface(tool.key))], store: store) == nil)
        #expect(HanlinChatContentProjection(runID: run, messageID: message,
            parts: [.init(id: UUID(), content: .markdown(String(repeating: "x", count: 1_048_577)))], store: store) == nil)
        #expect(HanlinChatContentProjection(runID: run, messageID: message,
            parts: (0..<129).map { _ in .init(id: UUID(), content: .markdown("x")) }, store: store) == nil)
    }

    @Test func modelProjectionNeverFollowsReplacedGeneration() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let run = UUID(), message = UUID(), part = UUID()
        let p = try #require(store.registerModelPart(runID: run, messageID: message, partID: part, sink: sink))
        try load(store, p)
        let surface = HanlinChatContentProjection.Part(id: part, content: .surface(p.key))
        let projection = try #require(HanlinChatContentProjection(runID: run, messageID: message, parts: [surface], store: store))
        store.seal(p.key)
        #expect(projection.surface(for: surface)?.isReadOnly == true)
        store.discard(p.key)
        let next = try #require(store.registerModelPart(runID: run, messageID: message, partID: part, sink: sink))
        #expect(next.key.generation != p.key.generation)
        #expect(projection.surface(for: surface) == nil)
        #expect(projection.surface(for: .init(id: part, content: .surface(next.key))) == nil)
        #expect(HanlinChatContentProjection(runID: run, messageID: message, parts: [surface], store: store) == nil)
        store.discardRun(run)
        #expect(store.registerModelPart(runID: run, messageID: message, partID: UUID(), sink: sink) == nil)
    }

    private func load(_ session: HanlinA2UISession, fixture: String = "form") throws {
        for line in try A2UIFixture.lines(fixture) { try session.receive(line).get() }
    }

    private func node(_ session: HanlinA2UISession, id: String, surface: String = "form-a") throws -> Node {
        var pending = [try #require(session.surface(surface)?.rootNode)]
        while let candidate = pending.popLast() {
            if candidate.id == id { return candidate }
            pending.append(contentsOf: candidate.allChildNodes)
        }
        throw A2UICheckFailure(description: "Missing SDK node \(id)")
    }

    private func load(_ store: HanlinA2UIResultStore, _ projection: HanlinA2UIResultProjection,
                      fixture: String = "form", startingAt: UInt64 = 0) throws {
        for (offset, line) in try A2UIFixture.lines(fixture).enumerated() {
            try store.receive(line, sequence: startingAt + UInt64(offset), for: projection.key).get()
        }
    }

    private func node(_ projection: HanlinA2UIResultProjection, id: String) throws -> Node {
        var pending = [try #require(projection.surface("form-a")?.rootNode)]
        while let candidate = pending.popLast() {
            if candidate.id == id { return candidate }
            pending.append(contentsOf: candidate.allChildNodes)
        }
        throw A2UICheckFailure(description: "Missing owned SDK node \(id)")
    }

    private func admissionFailure(_ result: Result<Void, HanlinA2UIResultAdmissionError>) -> HanlinA2UIResultAdmissionError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    @Test func transientOwnerLookupKeepsWireIDsIndependent() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let run = UUID(), result = UUID()
        let a = try #require(store.register(runID: run, resultID: result, callID: "call-a", sink: sink))
        let b = try #require(store.register(runID: UUID(), resultID: result, callID: "call-a", sink: sink))
        #expect(a.key.generation != b.key.generation)
        #expect(store.register(runID: run, resultID: result, callID: "call-b", sink: sink) == nil)
        try load(store, a)
        try load(store, b)
        let model = try #require(a.surface("form-a"))
        let identity = try node(a, id: "name").identity
        for _ in 0..<20 {
            let same = try #require(store.projection(for: a.key))
            #expect(same.surface("form-a") === model)
            #expect(try node(same, id: "name").identity == identity)
        }
        A2UITextField(node: try node(a, id: "name")).valueBinding.wrappedValue = "Private"
        #expect(try node(b, id: "greeting").string(for: "text") == "Ada")
        // Lookup did not replay input or consume its next ordinal.
        try load(store, a, fixture: "update", startingAt: 3)
        #expect(try node(a, id: "name").identity == identity)
        #expect(try node(a, id: "greeting").string(for: "text") == "Grace")
    }

    @Test func transientReceiveRejectsWrongIdentityAndSequence() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        let key = p.key
        let wrong = [
            HanlinA2UIResultKey(runID: UUID(), resultID: key.resultID, callID: key.callID, generation: key.generation),
            HanlinA2UIResultKey(runID: key.runID, resultID: UUID(), callID: key.callID, generation: key.generation),
            HanlinA2UIResultKey(runID: key.runID, resultID: key.resultID, callID: "foreign", generation: key.generation),
            HanlinA2UIResultKey(runID: key.runID, resultID: key.resultID, callID: key.callID, generation: UUID())
        ]
        let lines = try A2UIFixture.lines("form")
        for foreign in wrong {
            #expect(store.projection(for: foreign) == nil)
            #expect(admissionFailure(store.receive(lines[0], sequence: 0, for: foreign)) == .unregisteredResult)
            #expect(!store.seal(foreign) && !store.discard(foreign))
        }
        #expect(admissionFailure(store.receive(lines[0], sequence: 1, for: key)) == .outOfOrder)
        #expect(p.surfaceIDs.isEmpty)
        try store.receive(lines[0], sequence: 0, for: key).get()
        #expect(admissionFailure(store.receive(lines[0], sequence: 0, for: key)) == .outOfOrder)
        // Invalid content is rejected by real ingress/SDK, but that delivery is consumed once.
        #expect(admissionFailure(store.receive("{", sequence: 1, for: key)) == .rejected(.init(.malformedEnvelope)))
        #expect(admissionFailure(store.receive(lines[1], sequence: 1, for: key)) == .outOfOrder)
        try store.receive(lines[1], sequence: 2, for: key).get()
        try store.receive(lines[2], sequence: 3, for: key).get()
        #expect(try node(p, id: "greeting").string(for: "text") == "Ada")
        // Half a frame is never buffered or joined with the next delivery.
        #expect(admissionFailure(store.receive(String(lines[0].prefix(20)), sequence: 4, for: key)) == .rejected(.init(.malformedEnvelope)))
    }

    @Test func sealedResultRetainsModelsAndRevokesActions() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        let identity = try node(p, id: "name").identity
        let action = try #require(try node(p, id: "submit").action(for: "action", userActivation: true))
        action() // Queued in the real SDK relay, then revoked before actor delivery.
        #expect(store.seal(p.key) && store.seal(p.key))
        action() // Retained action cannot continue the expired run.
        #expect(p.isReadOnly && !p.isClosed && p.surface("form-a") === model)
        #expect(try node(p, id: "name").identity == identity)
        #expect(try node(p, id: "greeting").string(for: "text") == "Ada")
        #expect(admissionFailure(store.receive(try #require(A2UIFixture.lines("update").first), sequence: 3, for: p.key)) == .inputSealed)
        try await sink.recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "A sealed owner delivered an event")
        #expect(sink.keys.isEmpty && sink.recorder.snapshot.isEmpty)
    }

    @Test func sealingRunDoesNotRevokeOtherRun() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let a = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        let b = try #require(store.register(runID: UUID(), resultID: a.key.resultID, callID: "call", sink: sink))
        try load(store, a)
        try load(store, b)
        store.sealRun(a.key.runID)
        #expect(store.register(runID: a.key.runID, resultID: UUID(), callID: "late", sink: sink) == nil)
        #expect(store.replace(a.key, callID: "continuation", sink: sink) == nil)
        let action = try #require(try node(b, id: "submit").action(for: "action", userActivation: true))
        action()
        let event = try await nextA2UIValue(sink.recorder.stream)
        guard case .action(let resolved) = event else { Issue.record("Expected owned Button event"); return }
        #expect(resolved.context["name"]?.stringValue == "Ada")
        #expect(sink.keys == [b.key] && a.isReadOnly && !b.isReadOnly)
        #expect(a.surface("form-a")?.agentFunctionCaller == nil && b.surface("form-a")?.agentFunctionCaller == nil)
    }

    @Test func replacementRevokesOldGenerationBeforeNewDelivery() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let old = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "old", sink: sink))
        try load(store, old)
        let action = try #require(try node(old, id: "submit").action(for: "action", userActivation: true))
        action()
        let next = try #require(store.replace(old.key, callID: "new", sink: sink))
        #expect(old.isClosed && old.surfaceIDs.isEmpty && store.projection(for: old.key) == nil)
        #expect(next.key.runID == old.key.runID && next.key.resultID == old.key.resultID)
        #expect(next.key.callID == "new" && next.key.generation != old.key.generation)
        #expect(store.replace(old.key, callID: "stale", sink: sink) == nil)
        #expect(!store.discard(old.key))
        try load(store, next)
        action()
        #expect(admissionFailure(store.receive(try #require(A2UIFixture.lines("form").first), sequence: 3, for: old.key)) == .unregisteredResult)
        let nextAction = try #require(try node(next, id: "submit").action(for: "action", userActivation: true))
        nextAction()
        _ = try await nextA2UIValue(sink.recorder.stream)
        try await sink.recorder.requireQuiet(expectedCount: 1,
                                        failureMessage: "Replacement leaked an extra event")
        #expect(sink.keys == [next.key])
    }

    @Test func endingResultCancelsOwnedReceiveTask() async throws {
        for sealOnly in [true, false] {
            let store = HanlinA2UIResultStore()
            defer { store.discardAll() }
            let sink = A2UIResultSinkRecorder()
            let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
            try load(store, p)
            let state = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(4))
            let lateFrame = try #require(A2UIFixture.lines("update").first)
            let receiver = Task { @MainActor in
                defer { state.continuation.finish() }
                state.continuation.yield("started")
                do { try await Task.sleep(for: .seconds(30)); state.continuation.yield("unexpected timeout") }
                catch is CancellationError {
                    let result = store.receive(lateFrame, sequence: 3, for: p.key)
                    let expected: HanlinA2UIResultAdmissionError = sealOnly ? .inputSealed : .unregisteredResult
                    state.continuation.yield(admissionFailure(result) == expected ? "cancelled and rejected" : "late frame accepted")
                } catch { state.continuation.yield("unexpected error") }
            }
            defer { receiver.cancel() }
            #expect(store.attachReceiveTask(receiver, for: p.key))
            #expect(try await nextA2UIValue(state.stream) == "started")
            if sealOnly { store.sealRun(p.key.runID); store.sealRun(p.key.runID) }
            else { store.discardRun(p.key.runID); store.discardRun(p.key.runID) }
            #expect(try await nextA2UIValue(state.stream) == "cancelled and rejected")
            #expect(p.isReadOnly && p.isClosed == !sealOnly)
            #expect(store.register(runID: p.key.runID, resultID: UUID(), callID: "late", sink: sink) == nil)
            let rejectedTask = Task { @MainActor in }
            #expect(!store.attachReceiveTask(rejectedTask, for: p.key) && rejectedTask.isCancelled)
        }
    }

    @Test func presentationCopiesDoNotOwnDiscard() throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let model = try #require(p.surface("form-a"))
        var inline = store.projection(for: p.key)
        let expanded = try #require(store.projection(for: p.key))
        _ = HanlinA2UIProjectedResultView(projection: try #require(inline)).body
        _ = HanlinA2UIProjectedResultView(projection: expanded).body
        inline = nil
        #expect(!expanded.isClosed && expanded.surface("form-a") === model)
        #expect(store.projection(for: p.key)?.surface("form-a") === model)
        store.sealRun(p.key.runID)
        #expect(expanded.isReadOnly && expanded.surface("form-a") === model)
        #expect(store.discard(p.key) && !store.discard(p.key))
        #expect(expanded.isClosed && p.isClosed && expanded.surfaceIDs.isEmpty)
        store.discardAll()
        #expect(store.register(runID: UUID(), resultID: UUID(), callID: "late chat", sink: sink) == nil)
        // View construction/copy lifetime only; actual sheet/scroll behavior needs hosted UI.
    }

    @Test func eventSinkIsWeakAndCannotKeepAuthorityAlive() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let recorder = A2UIEventRecorder()
        var sink: A2UIResultSinkRecorder? = A2UIResultSinkRecorder(recorder: recorder)
        weak var weakSink = sink
        // Keep macro expansion and the unwrapped strong reference inside a returning
        // helper frame. No unwrapped sink can remain alive across the caller's sink=nil.
        @MainActor func register(_ candidate: A2UIResultSinkRecorder?) throws -> HanlinA2UIResultProjection {
            let liveSink = try #require(candidate)
            let registered = store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: liveSink)
            return try #require(registered)
        }
        let p = try register(sink)
        try load(store, p)
        let action = try #require(try node(p, id: "submit").action(for: "action", userActivation: true))
        action()
        sink = nil
        #expect(weakSink == nil)
        action()
        try await recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "An event escaped after its weak sink was released")
        #expect(recorder.snapshot.isEmpty && !p.isClosed)

        // A presentation may outlive its registration store; it retains models, not authority.
        let liveSink = A2UIResultSinkRecorder(recorder: recorder)
        var registration: HanlinA2UIResultStore? = HanlinA2UIResultStore()
        weak var weakRegistration = registration
        let retained = try #require(registration?.register(runID: UUID(), resultID: UUID(), callID: "other", sink: liveSink))
        try load(try #require(registration), retained)
        let retainedAction = try #require(try node(retained, id: "submit").action(for: "action", userActivation: true))
        retainedAction()
        registration = nil
        #expect(weakRegistration == nil)
        retainedAction()
        try await recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "A retained presentation acquired authority without its registration store")
        #expect(recorder.snapshot.isEmpty)
    }

    @Test func deletedSurfaceDropsQueuedOwnedEvents() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let p = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, p)
        let action = try #require(try node(p, id: "submit").action(for: "action", userActivation: true))
        action()
        try store.receive(#"{"version":"1.0","deleteSurface":{"surfaceId":"form-a"}}"#, sequence: 3, for: p.key).get()
        action()
        #expect(p.surfaceIDs.isEmpty && !p.isReadOnly)
        try await sink.recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "An event escaped its removed SDK surface")
        #expect(sink.keys.isEmpty)
    }

    @Test func retiredSurfaceCannotReanimateQueuedEventsInSameResult() async throws {
        let store = HanlinA2UIResultStore()
        defer { store.discardAll() }
        let sink = A2UIResultSinkRecorder()
        let old = try #require(store.register(runID: UUID(), resultID: UUID(), callID: "call", sink: sink))
        try load(store, old)
        let oldModel = try #require(old.surface("form-a"))
        let oldAction = try #require(try node(old, id: "submit").action(for: "action", userActivation: true))
        oldAction() // Emit before deletion; do not yield to either actor relay yet.
        try store.receive(#"{"version":"1.0","deleteSurface":{"surfaceId":"form-a"}}"#,
                          sequence: 3, for: old.key).get()
        // Attempt complete same-ID recreation before queued delivery. The conservative
        // result policy refuses it, rather than mistaking a new model for the old emitter.
        for (offset, line) in try A2UIFixture.lines("form").enumerated() {
            #expect(admissionFailure(store.receive(line, sequence: 4 + UInt64(offset), for: old.key)) == .retiredSurfaceID)
        }
        #expect(old.surface("form-a") == nil && old.surfaceIDs.isEmpty)
        oldAction()
        try await sink.recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "An old action acquired a deleted surface ID's new lifetime")
        #expect(sink.keys.isEmpty)

        // A raw/unowned delete grants no retirement authority, even in another live owner
        // using the same wire ID. This is a per-result policy, never a global ID blacklist.
        let independentSink = A2UIResultSinkRecorder()
        let independent = try #require(store.register(runID: old.key.runID, resultID: UUID(), callID: "other", sink: independentSink))
        _ = store.receive(#"{"version":"1.0","deleteSurface":{"surfaceId":"form-a"}}"#,
                          sequence: 0, for: independent.key)
        try await independentSink.recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "An unowned delete acquired callback correlation")
        try load(store, independent, startingAt: 1)
        let independentAction = try #require(try node(independent, id: "submit").action(for: "action", userActivation: true))
        independentAction()
        let independentEvent = try await nextA2UIValue(independentSink.recorder.stream)
        guard case .action(let independentResolved) = independentEvent else {
            Issue.record("Expected the independent owner's real SDK action")
            return
        }
        #expect(independentResolved.surfaceID == "form-a" && independentResolved.context["name"]?.stringValue == "Ada")
        #expect(independentSink.keys == [independent.key])

        let fresh = try #require(store.replace(old.key, callID: old.key.callID, sink: sink))
        try load(store, fresh)
        #expect(fresh.surface("form-a") !== oldModel && fresh.key.generation != old.key.generation)
        oldAction() // Still cannot acquire this fresh result generation's registration.
        let freshAction = try #require(try node(fresh, id: "submit").action(for: "action", userActivation: true))
        freshAction()
        let event = try await nextA2UIValue(sink.recorder.stream)
        guard case .action(let action) = event else { Issue.record("Expected fresh SDK action"); return }
        #expect(action.surfaceID == "form-a" && action.context["name"]?.stringValue == "Ada")
        try await sink.recorder.requireQuiet(expectedCount: 1,
                                        failureMessage: "A retired action escaped after fresh registration")
        #expect(sink.keys == [fresh.key])
    }

    private func requireNoCallbackCanary(_ event: RendererToAgentMessage) throws {
        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RendererToAgentMessage.self, from: encoded)
        let json = String(decoding: encoded, as: UTF8.self)
        var renderings = [json, String(describing: event), String(reflecting: event), String(reflecting: decoded)]
        if case .error(let error) = event {
            switch error {
            case .validationFailed(let failure):
                renderings += [failure.code.rawValue, failure.surfaceID, failure.path, failure.message,
                               failure.localizedDescription, String(reflecting: failure)]
            case .generic(let failure):
                renderings += [failure.code, failure.surfaceID ?? "", failure.functionCallID ?? "",
                               failure.message, failure.expression ?? "", failure.localizedDescription,
                               String(reflecting: failure)]
            }
        }
        let leaked = renderings.contains { $0.contains(diagnosticCanary) }
        try requireA2UI(!leaked, "Private canary escaped a diagnostic callback/encoding")
    }

    @Test func parsesAndRendersTextCardInputButton() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        #expect(try node(session, id: "root").type == "Card")
        #expect(try node(session, id: "greeting").string(for: "text") == "Ada")
        #expect(try node(session, id: "name").type == "TextField")
        #expect(try node(session, id: "submit").type == "Button")
        let catalog = BasicCatalogImplementation.makeCatalog(version: .v10)
        #expect(Surface.render(node: try node(session, id: "root"), using: [catalog.id: catalog]) != nil)
    }

    @Test func nativeInputBindingWritesAndReadsOfficialModel() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        let input = A2UITextField(node: try node(session, id: "name"))
        input.valueBinding.wrappedValue = "User edit"
        #expect(session.surface("form-a")?.dataModel.get("/name")?.stringValue == "User edit")
        #expect(try node(session, id: "greeting").string(for: "text") == "User edit")
        try load(session, fixture: "update")
        #expect(A2UITextField(node: try node(session, id: "name")).valueBinding.wrappedValue == "Grace")
    }

    @Test func stableIDsAndNodeIdentityAcrossUpdates() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        let input = try node(session, id: "name")
        let root = try node(session, id: "root")
        try load(session, fixture: "update")
        #expect(try node(session, id: "name").identity == input.identity)
        #expect(try node(session, id: "root").identity == root.identity)
        #expect(try node(session, id: "submitLabel").string(for: "text") == "Send")
    }

    @Test func malformedAndUnknownContentFallsBackAndRecovers() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        let malformed = String(decoding: try A2UIFixture.data("malformed", extension: "txt"), as: UTF8.self)
        _ = session.receive(malformed)
        #expect(session.unroutedFailure == .malformedEnvelope && session.surfaceIDs.isEmpty)
        try load(session)
        #expect(session.unroutedFailure == nil)
        _ = session.receive(malformed)
        #expect(session.unroutedFailure == nil && session.failures.isEmpty)
        for line in try A2UIFixture.lines("unknown") { #expect(throws: HanlinA2UIIngress.Rejection.self) { try session.receive(line).get() } }
        #expect(session.failures["form-a"] == .sdkValidation)
        try load(session, fixture: "update")
        #expect(session.failures.isEmpty && session.unroutedFailure == nil)
    }

    @Test func officialSchemasRejectInvalidTextInputButton() async throws {
        let invalid = try A2UIFixture.lines("invalid-components")
        #expect(invalid.count == 4)
        for (index, line) in invalid.enumerated() {
            let session = HanlinA2UISession(onEvent: { _ in })
            try load(session)
            let result = session.receive(line)
            #expect(throws: HanlinA2UIIngress.Rejection.self) { try result.get() }
            #expect(session.failures["form-a"] == .sdkValidation)
            if index == 3, case .failure(let rejection) = result {
                // Preserve the original invalid identifier as a real SDK rejection regression.
                #expect(rejection.diagnostics.contains { $0.code == "invalid_identifier" })
                #expect(rejection.sdkErrorType?.hasSuffix("A2UIValidationError") == true)
            }
        }
        let recorder = A2UIEventRecorder()
        let session = HanlinA2UISession(onEvent: { recorder.record($0) })
        try load(session)
        let message = #"{"version":"1.0","updateComponents":{"surfaceId":"form-a","components":[{"id":""#
            + diagnosticCanary + #"-component","component":"Text","text":"Rejected"}]}}"#
        guard case .failure(let rejection) = session.receive(message) else {
            Issue.record("SDK accepted an invalid canary component identifier")
            return
        }
        #expect(rejection.diagnostics.contains { $0.code == "invalid_identifier" })
        #expect(rejection.sdkErrorType == "A2UIValidationError")
        try requireNoDiagnosticCanary(rejection)
        let event = try await nextA2UIValue(recorder.stream)
        guard case .error = event else { Issue.record("Expected sanitized SDK error callback"); return }
        for recorded in recorder.snapshot { try requireNoCallbackCanary(recorded) }
        session.close()
    }

    @Test func independentSurfacesKeepModelsSeparate() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        for line in try A2UIFixture.lines("form") {
            try session.receive(line.replacingOccurrences(of: "form-a", with: "form-b")).get()
        }
        A2UITextField(node: try node(session, id: "name")).valueBinding.wrappedValue = "Only A"
        #expect(try node(session, id: "greeting", surface: "form-b").string(for: "text") == "Ada")
        _ = session.receive(try #require(A2UIFixture.lines("unknown").first))
        #expect(session.failures["form-b"] == nil)
        #expect(session.surfaceIDs == ["form-a", "form-b"])
    }

    @Test func independentOwnersCanReuseWireSurfaceID() throws {
        let first = HanlinA2UISession(onEvent: { _ in })
        let second = HanlinA2UISession(onEvent: { _ in })
        try load(first)
        try load(second)
        A2UITextField(node: try node(first, id: "name")).valueBinding.wrappedValue = "Private"
        #expect(try node(second, id: "greeting").string(for: "text") == "Ada")
    }

    @Test func deleteDisposesAndRecreateStartsWithNewIdentity() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        let oldNode = try node(session, id: "name")
        try session.receive(#"{"version":"1.0","deleteSurface":{"surfaceId":"form-a"}}"#).get()
        #expect(session.surface("form-a") == nil && session.surfaceIDs.isEmpty)
        try load(session)
        #expect(try node(session, id: "name").identity != oldNode.identity)
        #expect(session.surface("form-a")?.dataModel.get("/name")?.stringValue == "Ada")
    }

    @Test func closeRejectsLateFramesAndDisposesSurfaces() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        session.close()
        #expect(session.surfaceIDs.isEmpty && session.surface("form-a") == nil)
        #expect(throws: HanlinA2UIIngress.Rejection.self) { try load(session) }
        #expect(session.surfaceIDs.isEmpty)
    }

    @Test func buttonEventUsesCurrentBoundValue() async throws {
        let recorder = A2UIEventRecorder()
        let session = HanlinA2UISession(onEvent: { recorder.record($0) })
        try load(session)
        A2UITextField(node: try node(session, id: "name")).valueBinding.wrappedValue = "Changed"
        let action = try #require(try node(session, id: "submit").action(for: "action", userActivation: true))
        action()
        let event = try await nextA2UIValue(recorder.stream)
        guard case .action = event else {
            Issue.record("Expected the resolved Button event, got \(event)")
            return
        }
        let actions = recorder.snapshot.compactMap { event -> RendererAction? in
            if case .action(let action) = event { return action }
            return nil
        }
        let emitted = try #require(actions.last)
        #expect(actions.count == 1 && emitted.name == "submit")
        #expect(emitted.surfaceID == "form-a" && emitted.sourceComponentID == "submit")
        #expect(emitted.context["name"]?.stringValue == "Changed")
    }

    @Test func hebrewFixtureRetainsBindingsInRTLComposition() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session, fixture: "rtl")
        let input = A2UITextField(node: try node(session, id: "name", surface: "rtl-a"))
        #expect(input.valueBinding.wrappedValue == "שלום")
        input.valueBinding.wrappedValue = "דוד"
        #expect(try node(session, id: "greeting", surface: "rtl-a").string(for: "text") == "דוד")
        // Construction proof only; hosted layout/VoiceOver/Dynamic Type are a separate UI gate.
        _ = HanlinA2UIResultView(session: session)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "he"))
            .environment(\.dynamicTypeSize, .accessibility3)
    }

    @Test func surfaceLimitDoesNotRemoveExistingContent() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        let create = try #require(A2UIFixture.lines("form").first)
        for index in 0..<HanlinA2UISession.maximumSurfaces {
            try session.receive(create.replacingOccurrences(of: "form-a", with: "surface-\(index)")).get()
        }
        #expect(throws: HanlinA2UIIngress.Rejection.self) { try session.receive(create).get() }
        #expect(session.failures.isEmpty && session.unroutedFailure == nil)
        #expect(session.surfaceIDs.count == HanlinA2UISession.maximumSurfaces)
        #expect(session.surface("surface-0") != nil && session.surface("form-a") == nil)

        // The byte-budget gate runs after Frame validation. A budget rejection for an existing
        // owner's update/delete is correlated; an untrusted ID cannot choose another fallback.
        let budgetSession = HanlinA2UISession(onEvent: { _ in })
        var consumed = 0
        for id in ["form-a", "form-b"] {
            for line in try A2UIFixture.lines("form") {
                let message = line.replacingOccurrences(of: "form-a", with: id)
                try budgetSession.receive(message).get()
                consumed += message.utf8.count
            }
        }
        let first = try #require(budgetSession.surface("form-a"))
        let second = try #require(budgetSession.surface("form-b"))
        let prefix = #"{"version":"1.0","updateDataModel":{"surfaceId":"form-a","path":"/budgetProbe","value":""#
        let suffix = #""}}"#
        let overhead = prefix.utf8.count + suffix.utf8.count
        while consumed < HanlinA2UISession.maximumSessionBytes {
            let remaining = HanlinA2UISession.maximumSessionBytes - consumed
            try requireA2UI(remaining >= overhead, "Budget fixture cannot fill the exact remaining bytes")
            let bytes = min(remaining, HanlinA2UIIngress.maximumMessageBytes)
            let message = prefix + String(repeating: "x", count: bytes - overhead) + suffix
            try budgetSession.receive(message).get()
            consumed += message.utf8.count
        }
        #expect(consumed == HanlinA2UISession.maximumSessionBytes && budgetSession.failures.isEmpty)
        for message in [
            #"{"version":"1.0","updateDataModel":{"surfaceId":"form-a","path":"/name","value":"Must not apply"}}"#,
            #"{"version":"1.0","deleteSurface":{"surfaceId":"form-a"}}"#
        ] {
            guard case .failure(let rejection) = budgetSession.receive(message) else {
                Issue.record("An exhausted session accepted a mutation")
                return
            }
            #expect(rejection.failure == .sessionBudget && rejection.surfaceID == "form-a")
            #expect(budgetSession.failures == ["form-a": .sessionBudget])
            #expect(budgetSession.surface("form-a") === first && budgetSession.surface("form-b") === second)
            #expect(budgetSession.surfaceIDs == ["form-a", "form-b"] && budgetSession.unroutedFailure == nil)
            #expect(first.dataModel.get("/name")?.stringValue == "Ada")
            #expect(second.dataModel.get("/name")?.stringValue == "Ada")
        }
        budgetSession.close()
    }

    @Test func rejectedSurfaceIDsCannotGrowFallbackStorageWithoutBound() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        let unknown = try #require(A2UIFixture.lines("unknown").first)
        for index in 0..<20 {
            _ = session.receive(unknown.replacingOccurrences(of: "form-a", with: "missing-\(index)"))
        }
        #expect(session.failures.isEmpty && session.unroutedFailure == nil)
        #expect(session.surfaceIDs == ["form-a"])
        #expect(session.surface("form-a")?.dataModel.get("/name")?.stringValue == "Ada")
    }

    @Test func unsupportedOperationsCannotCreateOrRerouteOwnedSurfaceFallbacks() throws {
        let session = HanlinA2UISession(onEvent: { _ in })
        let foreignOwner = HanlinA2UISession(onEvent: { _ in })
        try load(session)
        for line in try A2UIFixture.lines("form") {
            try session.receive(line.replacingOccurrences(of: "form-a", with: "form-b")).get()
            try foreignOwner.receive(line.replacingOccurrences(of: "form-a", with: "form-foreign")).get()
        }
        let first = try #require(session.surface("form-a"))
        let second = try #require(session.surface("form-b"))
        let foreign = try #require(foreignOwner.surface("form-foreign"))
        let firstIdentity = try node(session, id: "name").identity
        for message in try A2UIUncorrelatedInputs.messages() {
            guard case .failure(let rejection) = session.receive(message) else {
                Issue.record("Unsupported envelope was accepted")
                return
            }
            #expect(rejection.failure == .unsupportedOperation && rejection.surfaceID == nil)
            #expect(session.surfaceIDs == ["form-a", "form-b"])
            #expect(session.failures.isEmpty && session.unroutedFailure == nil)
            #expect(session.surface("form-a") === first && session.surface("form-b") === second)
            #expect(session.surface("form-foreign") == nil)
            #expect(try node(session, id: "name").identity == firstIdentity)
            #expect(first.dataModel.get("/name")?.stringValue == "Ada")
            #expect(second.dataModel.get("/name")?.stringValue == "Ada")
            #expect(foreignOwner.surface("form-foreign") === foreign && foreignOwner.failures.isEmpty)
        }
        // A real, correlated SDK validation error still falls back for its own surface only.
        _ = session.receive(try #require(A2UIFixture.lines("unknown").first))
        #expect(session.failures == ["form-a": .sdkValidation])
        for message in try A2UIUncorrelatedInputs.messages() { _ = session.receive(message) }
        #expect(session.failures == ["form-a": .sdkValidation])
        #expect(session.surfaceIDs == ["form-a", "form-b"] && session.unroutedFailure == nil)
        #expect(second.dataModel.get("/name")?.stringValue == "Ada")
        session.close()
        foreignOwner.close()
    }

    @Test func unknownFunctionsAndUnsolicitedResponsesCannotEnableRPC() async throws {
        let recorder = A2UIEventRecorder()
        let session = HanlinA2UISession(onEvent: { recorder.record($0) })
        try load(session)
        let surface = try #require(session.surface("form-a"))
        #expect(surface.agentFunctionCaller == nil)
        do {
            _ = try await surface.callAgentFunction(AgentFunctionCall(
                name: "lookupNotAuthorized", catalogID: HanlinA2UIIngress.catalogID
            ))
            Issue.record("An agent call succeeded without permission")
        } catch let error as FunctionError {
            #expect(error.rpcCode == "NO_LISTENER")
        }
        for line in try A2UIFixture.lines("unknown-function") {
            #expect(throws: HanlinA2UIIngress.Rejection.self) { try session.receive(line).get() }
            let event = try await nextA2UIValue(recorder.stream)
            guard case .error = event else {
                Issue.record("Unknown function emitted an outbound request: \(event)")
                return
            }
        }
        for (function, argument) in [(diagnosticCanary + "-function", "value"),
                                     ("formatNumber", diagnosticCanary + "-argument")] {
            let privateRecorder = A2UIEventRecorder()
            let privateSession = HanlinA2UISession(onEvent: { privateRecorder.record($0) })
            try load(privateSession)
            var arguments: [String: Any] = [argument: "Rejected"]
            if function == "formatNumber" { arguments["value"] = 1 }
            let payload: [String: Any] = ["version": "1.0", "updateComponents": [
                "surfaceId": "form-a", "components": [["id": "greeting", "component": "Text",
                "text": ["@call": function, "args": arguments]]]
            ]]
            let message = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            guard case .failure(let rejection) = privateSession.receive(message) else {
                Issue.record("SDK accepted invalid function/argument canary identifiers")
                return
            }
            #expect(rejection.diagnostics.contains { $0.code == "invalid_identifier" })
            try requireNoDiagnosticCanary(rejection)
            let event = try await nextA2UIValue(privateRecorder.stream)
            guard case .error = event else { Issue.record("Unexpected canary RPC request"); return }
            for recorded in privateRecorder.snapshot { try requireNoCallbackCanary(recorded) }
            #expect(privateSession.surface("form-a")?.agentFunctionCaller == nil)
            privateSession.close()
        }
        let response = session.receive(#"{"version":"1.0","agentFunctionResponse":{"functionCallId":"unsolicited","value":"x"}}"#)
        guard case .failure(let rejection) = response else {
            Issue.record("An unsolicited RPC response was accepted")
            return
        }
        #expect(rejection.failure == .unsupportedOperation)
        #expect(surface.agentFunctionCaller == nil)
        #expect(!recorder.snapshot.contains { if case .callAgentFunction = $0 { return true }; return false })
        session.close()
    }

    @Test func closeRevokesQueuedAndRetainedActionCallbacks() async throws {
        let recorder = A2UIEventRecorder()
        let session = HanlinA2UISession(onEvent: { recorder.record($0) })
        try load(session)
        let action = try #require(try node(session, id: "submit").action(for: "action", userActivation: true))
        action() // The nonisolated SDK hook queues delivery to MainActor.
        session.close()
        session.close()
        action() // Retained SDK nodes/actions must not reach a closed owner's callback.
        try await recorder.requireQuiet(expectedCount: 0,
                                        failureMessage: "An action reached the owner after close")
        #expect(recorder.snapshot.isEmpty && session.isClosed)
    }

    #if DEBUG
    @Test func closeCancelsSeededInFlightSDKCallPromptlyAndOnlyOnce() async throws {
        let recorder = A2UIEventRecorder()
        let session = HanlinA2UISession(onEvent: { recorder.record($0) })
        try load(session)
        // Test-only real-SDK fault injection. Production never installs this listener.
        let processor = session.sdkProcessorForLifecycleTests
        processor.outboundListener = { recorder.record($0) }
        let completion = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let pending = Task { @MainActor in
            defer { completion.continuation.finish() }
            do {
                _ = try await processor.callAgentFunction(
                    surfaceID: "form-a", functionName: "pendingAtClose", version: .v10,
                    timeoutSeconds: 30
                )
                completion.continuation.yield("UNEXPECTED_SUCCESS")
            } catch let error as FunctionError {
                completion.continuation.yield(error.rpcCode)
            } catch {
                completion.continuation.yield("UNEXPECTED_ERROR")
            }
        }
        defer { pending.cancel(); session.close() }
        let outbound = try await nextA2UIValue(recorder.stream)
        guard case .callAgentFunction = outbound else {
            Issue.record("The SDK call was not in flight before close")
            return
        }
        session.close()
        session.close()
        // This 2s deadline is shorter than the SDK's 30s timeout; waiting for timeout cannot pass.
        #expect(try await nextA2UIValue(completion.stream) == "CANCELLED")
        #expect(session.surface("form-a") == nil && session.surfaceIDs.isEmpty)
        do {
            _ = try await processor.callAgentFunction(
                surfaceID: "form-a", functionName: "late", version: .v10
            )
            Issue.record("Disposed SDK processor accepted a new call")
        } catch let error as FunctionError {
            #expect(error.rpcCode == "DISPOSED")
        }
        try await recorder.requireQuiet(expectedCount: 1,
                                        failureMessage: "An SDK callback escaped disposal")
        #expect(recorder.snapshot.count == 1) // Only the test-seeded request before close.
    }
    #endif
}
#endif
#endif
