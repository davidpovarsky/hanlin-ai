#if HANLIN_A2UI_POC
import A2UICore
import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite(.serialized) @MainActor
struct HanlinA2UICompleteBatchValidatorTests {
    private typealias Validator = HanlinA2UICompleteBatchValidator

    private func fixture(message: UUID = UUID(), part: UUID = UUID()) throws -> [HanlinChatStructuredPart] {
        let url = try #require(Bundle.module.url(forResource: "form", withExtension: "jsonl", subdirectory: "A2UIFixtures"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").enumerated().map { index, json in
            try .init(messageID: message, partID: part, sequence: UInt64(index),
                      payload: .a2uiMessage(protocolVersion: "1.0", json: Data(json.utf8)))
        }
    }

    private func replacing(_ parts: [HanlinChatStructuredPart], at index: Int, json: String) throws -> [HanlinChatStructuredPart] {
        var result = parts
        let old = parts[index]
        result[index] = try .init(messageID: old.messageID, partID: old.partID, sequence: old.sequence,
                                 payload: .a2uiMessage(protocolVersion: "1.0", json: Data(json.utf8)))
        return result
    }

    @Test func completeBatchUsesOfficialSchemasAndResolvesForwardReferences() throws {
        let form = try fixture()
        try Validator.validate(form)
        let partial = try replacing(form, at: 1, json: #"{"version":"1.0","updateComponents":{"surfaceId":"form-a","components":[{"id":"root","component":"Card","child":"later"}]}}"#)
        let completed = try replacing(partial, at: 2, json: #"{"version":"1.0","updateComponents":{"surfaceId":"form-a","components":[{"id":"later","component":"Text","text":"Complete"}]}}"#)
        try Validator.validate(completed)
        // An exact canonical duplicate is suppressed rather than recreating the same surface.
        try Validator.validate([form[0], form[0]] + Array(form.dropFirst()))
    }

    @Test func finalGraphRejectsMissingRootDanglingReferencesAndSchemaErrors() throws {
        let form = try fixture()
        let dangling = try replacing(form, at: 2, json: #"{"version":"1.0","updateComponents":{"surfaceId":"form-a","components":[{"id":"root","component":"Card","child":"missing"}]}}"#)
        #expect(throws: Validator.Failure.incompleteGraph) { try Validator.validate(dangling) }
        #expect(throws: Validator.Failure.incompleteGraph) { try Validator.validate([form[0]]) }
        let invalid = try replacing(form, at: 2, json: #"{"version":"1.0","updateComponents":{"surfaceId":"form-a","components":[{"id":"root","component":"Text","text":42}]}}"#)
        #expect(throws: Validator.Failure.invalidFrame) { try Validator.validate(invalid) }
    }

    @Test func independentOwnersReuseWireAndPartIDsWithoutSharingGraphs() throws {
        let messageA = UUID(), messageB = UUID(), part = UUID()
        let first = try fixture(message: messageA, part: part)
        let second = try fixture(message: messageB, part: part)
        try Validator.validate(first + second)
        let broken = try replacing(first, at: 2, json: #"{"version":"1.0","updateComponents":{"surfaceId":"form-a","components":[{"id":"root","component":"Card","child":"greeting"}]}}"#)
        #expect(throws: Validator.Failure.incompleteGraph) { try Validator.validate(broken + second) }
        let deleted = try HanlinChatStructuredPart(messageID: messageA, partID: part, sequence: 3,
            payload: .a2uiMessage(protocolVersion: "1.0", json: Data(#"{"version":"1.0","deleteSurface":{"surfaceId":"form-a"}}"#.utf8)))
        try Validator.validate(first + [deleted] + second)
        let recreate = try HanlinChatStructuredPart(messageID: messageA, partID: part, sequence: 4, payload: first[0].payload)
        #expect(throws: Validator.Failure.invalidFrame) { try Validator.validate(first + [deleted, recreate]) }
    }

    @Test func wholeBatchFramingRejectsBeforeAnyScratchConstruction() throws {
        let first = try fixture()
        let malformed = try HanlinChatStructuredPart(messageID: UUID(), partID: UUID(), sequence: 0,
            payload: .a2uiMessage(protocolVersion: "1.0", json: Data("{PRIVATE_CANARY".utf8)))
        var disposed = 0
        #expect(throws: Validator.Failure.invalidFrame) {
            try Validator.validateForLifecycleTests(first + [malformed]) { _ in disposed += 1 }
        }
        #expect(disposed == 0)
        let rpc = try replacing(first, at: 2, json: #"{"version":"1.0","callRendererFunction":{"surfaceId":"form-a","functionCallId":"x","call":{"name":"openUrl","args":{"url":"https://example.com"}}}}"#)
        #expect(throws: Validator.Failure.invalidFrame) {
            try Validator.validateForLifecycleTests(rpc) { _ in disposed += 1 }
        }
        #expect(disposed == 0)
    }

    @Test func canonicalOrderKindsProtocolAndResourceBoundsArePreserved() throws {
        #expect(throws: Validator.Failure.emptyBatch) { try Validator.validate([]) }
        let parts = try fixture()
        #expect(throws: Validator.Failure.invalidSequence) { try Validator.validate([parts[1], parts[0]]) }
        let changedKind = try HanlinChatStructuredPart(messageID: parts[0].messageID, partID: parts[0].partID,
                                                      sequence: 1, payload: .textDelta("Changed kind"))
        #expect(throws: Validator.Failure.invalidSequence) { try Validator.validate([parts[0], changedKind]) }
        let future = try HanlinChatStructuredPart(messageID: UUID(), partID: UUID(), sequence: 0,
            payload: .a2uiMessage(protocolVersion: "v0.9", json: Data("{}".utf8)))
        #expect(throws: Validator.Failure.unsupportedProtocol) { try Validator.validate([future]) }
        #expect(throws: Validator.Failure.resourceLimit) {
            try Validator.validate(Array(repeating: parts[0], count: HanlinA2UIContentLimits.maximumFrames + 1))
        }
        let message = UUID(), textPart = UUID()
        let large = try HanlinChatStructuredPart(messageID: message, partID: textPart, sequence: 0,
            payload: .textDelta(String(repeating: "x", count: HanlinA2UIContentLimits.maximumTextBytesPerMessage)))
        let extra = try HanlinChatStructuredPart(messageID: message, partID: textPart, sequence: 1, payload: .textDelta("x"))
        #expect(throws: Validator.Failure.resourceLimit) { try Validator.validate([large, extra]) }
    }

    @Test func scratchProcessorsDisposeOnSuccessAndFailureWithoutRPCAuthority() throws {
        var retained: [HanlinA2UISession] = []
        let probe: (HanlinA2UISession) -> Void = { session in
            #expect(session.sdkProcessorForLifecycleTests.outboundListener == nil)
            retained.append(session)
        }
        let valid = try fixture()
        try Validator.validateForLifecycleTests(valid, onDisposing: probe)
        #expect(throws: Validator.Failure.incompleteGraph) {
            try Validator.validateForLifecycleTests([valid[0]], onDisposing: probe)
        }
        #expect(retained.count == 2)
        for session in retained {
            #expect(session.isClosed && session.surfaceIDs.isEmpty)
            #expect(session.sdkProcessorForLifecycleTests.surfaceGroupModel.surfacesMap.isEmpty)
            guard case .failure(let rejection) = session.receive("{}") else { Issue.record("Disposed scratch accepted input"); continue }
            #expect(rejection.failure == .closed)
        }
    }
}
#endif
