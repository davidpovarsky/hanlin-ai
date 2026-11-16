import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import HanlinSDKTestFixtures
import Testing

private actor RawBoundaryHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    let original: HanlinHostContext
    var inputs: [Data] = []
    init(_ original: HanlinHostContext) { self.original = original }
    func context(for session: HanlinHostSession) -> HanlinHostContext { original }
    func catalog(for context: HanlinHostContext) throws -> HanlinHostCatalog {
        .init(revision: .init(1), context: context,
              tools: [try SyntheticFixtureHost.tool("fixture_read", risk: .read, guarantee: .readOnly)])
    }
    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) throws -> HanlinHostExecutionResult {
        inputs.append(try #require(invocation.originalArgumentsJSON))
        return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: .completed([]), completedAt: .now), effectState: .confirmedNoEffect, context: original)
    }
    func cancel(_ invocation: HanlinToolInvocationID) {}
    func open(_ destination: HanlinHostDestination) throws -> HanlinHostNavigationResult { throw HanlinHostError.denied }
}

@Suite struct HostSchemaValidationTests {
    @Test func originalMCPWireSchemasPreserveExactNumbersAndScalarKeys() throws {
        let response = Data(#"{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"exact","inputSchema":{"type":"object","properties":{"n":{"const":9007199254740993},"é":{"type":"string"},"é":{"type":"number"}}}}]}}"#.utf8)
        let schemas = try HanlinHostSchemaValidation.mcpToolSchemas(responseJSON: response)
        let data = try #require(schemas[Data("exact".utf8).base64EncodedString()])
        let plan = try HanlinHostSchemaValidation(schemaJSON: data)
        try plan.validate(argumentsJSON: Data(#"{"n":9007199254740993,"é":"text","é":5}"#.utf8))
        #expect(throws: (any Error).self) { try plan.validate(argumentsJSON: Data(#"{"n":9007199254740992,"é":"text","é":5}"#.utf8)) }
    }

    @Test func originalMCPWireRejectsRepeatedNamesAndNonSchemaResponsesDoNotRegister() throws {
        let repeated = Data(#"{"result":{"tools":[{"name":"x","inputSchema":{}},{"name":"x","inputSchema":{}}]}}"#.utf8)
        #expect(throws: (any Error).self) { try HanlinHostSchemaValidation.mcpToolSchemas(responseJSON: repeated) }
        #expect(try HanlinHostSchemaValidation.mcpToolSchemas(responseJSON: Data(#"{"method":"notifications/tools/list_changed"}"#.utf8)).isEmpty)
    }
    private func bytes(_ value: String) -> Data { Data(value.utf8) }
    private func validator(_ schema: String) throws -> HanlinHostSchemaValidation { try .init(schemaJSON: bytes(schema)) }

    @Test func requiredTypeAndAdditionalAssertionsAdmitHebrewAndEmoji() throws {
        let plan = try validator(#"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false}"#)
        try plan.validate(argumentsJSON: bytes(#"{"text":"שלום🙂"}"#))
        for invalid in [#"{}"#, #"{"text":1}"#, #"{"text":"ok","extra":1}"#] {
            #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try plan.validate(argumentsJSON: bytes(invalid)) }
        }
    }

    @Test func localReferencesSiblingsAndLegalAnnotationsAreEvaluated() throws {
        let plan = try validator(##"{"$defs":{"positive":{"type":"integer","minimum":1}},"$ref":"#/$defs/positive","maximum":3,"description":"Legal annotation","x-host-note":"extension annotation"}"##)
        try plan.validate(argumentsJSON: bytes("2"))
        for invalid in ["0", "4", "1.1"] {
            #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try plan.validate(argumentsJSON: bytes(invalid)) }
        }
    }

    @Test func exactDecimalsDoNotMergeAtTwoTo53OrUseApproximateMultipleOf() throws {
        let boundary = try validator(#"{"const":9007199254740993}"#)
        try boundary.validate(argumentsJSON: bytes("9007199254740993"))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try boundary.validate(argumentsJSON: bytes("9007199254740992")) }
        let decimal = try validator(#"{"multipleOf":0.1}"#)
        try decimal.validate(argumentsJSON: bytes("0.3"))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try decimal.validate(argumentsJSON: bytes("0.30000000000000000001")) }
        let integer = try validator(#"{"multipleOf":1}"#)
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try integer.validate(argumentsJSON: bytes("1e-10")) }
    }

    @Test func distinctScalarStringsAndObjectKeysRemainDistinct() throws {
        let text = try validator(#"{"const":"K"}"#)
        try text.validate(argumentsJSON: bytes(#""K""#))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try text.validate(argumentsJSON: bytes(#""\u212A""#)) }
        let object = try validator(#"{"type":"object","required":["K","\u212A"],"properties":{"K":{"const":1},"\u212A":{"const":2}},"additionalProperties":false}"#)
        try object.validate(argumentsJSON: bytes(#"{"K":1,"\u212A":2}"#))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try object.validate(argumentsJSON: bytes(#"{"K":2}"#)) }
    }

    @Test func booleanSchemasAndUnicodeScalarLengthsAreStandard() throws {
        let never = try validator("false")
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try never.validate(argumentsJSON: bytes("null")) }
        let nested = try validator(#"{"type":"object","properties":{"forbidden":false}}"#)
        try nested.validate(argumentsJSON: bytes("{}"))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try nested.validate(argumentsJSON: bytes(#"{"forbidden":null}"#)) }
        let scalar = try validator(#"{"type":"string","maxLength":1}"#)
        try scalar.validate(argumentsJSON: bytes(#""🙂""#))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) { try scalar.validate(argumentsJSON: bytes(#""e\u0301""#)) }
    }

    @Test func offlineMissingResourcesAndUnsupportedRequiredVocabularyFailClosed() throws {
        #expect(throws: (any Error).self) { _ = try validator(#"{"$ref":"https://unavailable.example/schema"}"#) }
        #expect(throws: (any Error).self) { _ = try validator(#"{"$schema":"https://unavailable.example/dialect","$vocabulary":{"https://unavailable.example/vocab":true}}"#) }
    }

    @Test func actualProviderProjectionAndExecutorMetadataTransformMustBeFaithful() throws {
        #expect(try HanlinHostSchemaValidation.providerSchema(bytes(#"{"type":"object","description":"שלום🙂"}"#)) == bytes(#"{"type":"object","description":"שלום🙂"}"#))
        #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
            _ = try HanlinHostSchemaValidation.providerSchema(bytes(#"{"const":9007199254740993}"#))
        }
        #expect(throws: (any Error).self) {
            _ = try HanlinHostSchemaValidation.providerSchema(bytes(#"{"properties":{"K":{"const":1},"\u212A":{"const":2}}}"#))
        }
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: bytes(#"{"x":9007199254740993,"__summary":"visible"}"#),
            projectedJSON: bytes(#"{"x":9007199254740993}"#), removingMetadataKeys: ["__summary"])
        for projected in [#"{"x":9007199254740992}"#, #"{"x":9007199254740993,"changed":1}"#] {
            #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
                try HanlinHostSchemaValidation.requireSameValue(originalJSON: bytes(#"{"x":9007199254740993}"#), projectedJSON: bytes(projected))
            }
        }
        #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
            try HanlinHostSchemaValidation.requireSameValue(originalJSON: bytes("1.234567890123456789"), projectedJSON: bytes("1.2345678901234567"))
        }
    }

    @Test func finiteInputDepthAndCancellationFailWithoutVerdict() async throws {
        #expect(throws: HanlinHostSchemaValidation.Failure.inputTooLarge) { _ = try validator(String(repeating: " ", count: 1_048_577)) }
        let plan = try validator("true")
        #expect(throws: (any Error).self) { try plan.validate(argumentsJSON: bytes(String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65))) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try plan.validate(argumentsJSON: bytes("0"))
        }
        do { try await task.value; Issue.record("Cancelled validation returned a verdict") }
        catch { #expect(error is CancellationError) }
    }

    @Test func deterministicWriterKeepsExactDecimalsScalarKeysAndStableOrdering() throws {
        let first = try HanlinHostSchemaValidation.deterministicJSONData(bytes(#"{"z":9007199254740993,"K":1,"\u212A":2,"decimal":1.234567890123456789}"#))
        let reordered = try HanlinHostSchemaValidation.deterministicJSONData(bytes(#"{"decimal":1.234567890123456789,"\u212A":2,"K":1,"z":9007199254740993}"#))
        #expect(first == reordered)
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: first, projectedJSON: reordered)
        for changed in [#"{"z":9007199254740992,"K":1,"\u212A":2,"decimal":1.234567890123456789}"#,
                        #"{"z":9007199254740993,"K":1,"decimal":1.234567890123456789}"#,
                        #"{"z":9007199254740993,"K":1,"\u212A":2,"decimal":1.2345678901234567}"#] {
            #expect(first != (try HanlinHostSchemaValidation.deterministicJSONData(bytes(changed))))
        }
    }

    @Test func dispatcherRetainsOriginalBytesAndNeverReplaysAChangedRoundedValue() async throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let identity = HanlinHostSession(conversationID: UUID(), context: context)
        let host = RawBoundaryHost(context), dispatcher = HanlinHostDispatcher(host: host)
        let catalog = try await host.catalog(for: context), run = UUID()
        let original = #"{"text":"read","decimal":1.234567890123456789}"#
        let first = try await dispatcher.dispatchEvent(alias: "fixture_read", argumentsJSON: original, providerCallID: "same",
            runID: run, step: 0, session: identity, catalog: catalog, limits: .init())
        let replay = try await dispatcher.dispatchEvent(alias: "fixture_read", argumentsJSON: original, providerCallID: "same",
            runID: run, step: 0, session: identity, catalog: catalog, limits: .init())
        #expect(first.resultID == replay.resultID)
        do {
            _ = try await dispatcher.dispatchEvent(alias: "fixture_read", argumentsJSON: #"{"text":"read","decimal":1.2345678901234567}"#,
                providerCallID: "same", runID: run, step: 0, session: identity, catalog: catalog, limits: .init())
            Issue.record("Rounded input replayed an original receipt")
        } catch { #expect(error as? HanlinHostError == .idempotencyConflict) }
        #expect(await host.inputs == [bytes(original)])
    }
}
