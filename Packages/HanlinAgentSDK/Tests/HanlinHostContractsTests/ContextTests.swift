import Foundation
import HanlinHostContracts
import HanlinPlatformContracts
import Testing

@Suite struct ContextTests {
    @Test func hostManagedMutationRequiresExplicitMinorVersionAndRoundTripsWithoutDowngrade() throws {
        let value = HanlinHostWriteGuarantee.hostManagedMutation
        let encoded = try JSONEncoder().encode(value)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"hostManagedMutation\"")
        #expect(try JSONDecoder().decode(HanlinHostWriteGuarantee.self, from: encoded) == value)
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let logical = HanlinLogicalToolID(providerInstanceID: try .init(validating: "fixture"), localToolID: try .init(validating: "mutate"))
        let revision = try HanlinDescriptorRevision(1)
        let schema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(Data(#"{"type":"object"}"#.utf8), defaultDialect: .draft2020_12)
        let descriptor = HanlinToolDescriptor(logicalID: logical, descriptorRevision: revision, owner: .system,
            title: try .init(["en": "Mutation"]), summary: try .init(["en": "Host-managed mutation"]),
            inputSchema: schema, risk: .write, presentation: .init())
        let tool = HanlinHostTool(route: .init(alias: "mutate", logicalToolID: logical, descriptorRevision: revision),
            descriptor: descriptor, writeGuarantee: value)
        let old = HanlinHostCatalog(revision: .init(1), context: context, tools: [tool])
        #expect(throws: HanlinHostError.unsupportedVersion) { try old.validate() }
        try HanlinHostCatalog(apiVersion: .init(major: 1, minor: 1), revision: .init(1), context: context, tools: [tool]).validate()
    }
    @Test func decodedNamespacesCannotBypassValidation() throws {
        #expect(throws: HanlinHostError.invalidContext) {
            try JSONDecoder().decode(HanlinConversationNamespace.self, from: Data(#"{"app":"","account":"a","workspace":"w","space":"s"}"#.utf8))
        }
    }
    @Test func persistedPresentationCarriesNoExecutionAuthority() throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let record = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0,
            entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .presentationReference(version: 1, opaqueReference: "view-only"))])
        let decoded = try JSONDecoder().decode(HanlinConversationRecord.self, from: JSONEncoder().encode(record))
        try decoded.validate()
        #expect(decoded == record)
    }
    @Test func previousMetadataFormatRemainsReadableWithoutMutation() throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let original = HanlinConversationRecord(formatVersion: 1, namespace: ns, conversationID: UUID(), revision: 4,
            draft: "Preserve original", entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("History"))])
        let bytes = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(HanlinConversationRecord.self, from: bytes)
        try restored.validate()
        #expect(restored == original && restored.formatVersion == 1)
        #expect(HanlinConversationRecord.currentFormat == 2)
    }

    @Test func canonicalStructuredReplayKeepsExactBytesGlobalOrderAndDeduplicates() throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let run = UUID(), message = UUID(), text = UUID(), surface = UUID()
        let parts = try [
            HanlinChatStructuredPart(messageID: message, partID: text, sequence: 0, payload: .textDelta("Before")),
            HanlinChatStructuredPart(messageID: message, partID: surface, sequence: 1, payload: .a2uiMessage(protocolVersion: "v0.9", json: Data(#"{"createSurface":{"surfaceId":"hebrew-אב"}}"#.utf8))),
            HanlinChatStructuredPart(messageID: message, partID: text, sequence: 2, payload: .textDelta("After"))
        ]
        let record = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 1, entries: [
            .init(runID: run, step: 0, sequence: 0, payload: .structuredPart(parts[0], context: context)),
            .init(runID: run, step: 0, sequence: 1, payload: .reasoning("not part of displayed content")),
            .init(runID: run, step: 0, sequence: 2, payload: .structuredPart(parts[1], context: context)),
            .init(runID: run, step: 0, sequence: 3, payload: .structuredPart(parts[1], context: context)),
            .init(runID: run, step: 0, sequence: 4, payload: .structuredPart(parts[2], context: context)),
            .init(runID: run, step: 0, sequence: 5, payload: .failed(code: .cancelled))
        ])
        let restored = try JSONDecoder().decode(HanlinConversationRecord.self, from: JSONEncoder().encode(record))
        let entries = try restored.structuredEntries(runID: run, messageID: message)
        #expect(entries.map(\.sequence) == [0, 2, 4])
        let replay = entries.compactMap { entry -> HanlinChatStructuredPart? in
            if case .structuredPart(let part, let original) = entry.payload { #expect(original == context); return part }
            return nil
        }
        #expect(replay == parts)
        #expect(try restored.structuredEntries(runID: UUID(), messageID: message).isEmpty)
    }

    @Test func structuredReplayRejectsForeignScopeConflictsAndPartKindChanges() throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let foreign = try HanlinConversationNamespace(app: "a", account: "other", workspace: "w", space: "s")
        let context = HanlinHostContext(namespace: ns, sceneID: UUID(), generation: UUID())
        let run = UUID(), message = UUID(), partID = UUID()
        let part = try HanlinChatStructuredPart(messageID: message, partID: partID, sequence: 0, payload: .textDelta("Original"))
        let badContext = HanlinHostContext(namespace: foreign, sceneID: context.sceneID, generation: context.generation)
        let invalid = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0,
            entries: [.init(runID: run, step: 0, sequence: 0, payload: .structuredPart(part, context: badContext))])
        #expect(throws: HanlinHostError.invalidRecord) { try invalid.structuredEntries(runID: run, messageID: message) }
        let changed = try HanlinChatStructuredPart(messageID: message, partID: partID, sequence: 0, payload: .textDelta("Changed"))
        let conflict = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0, entries: [
            .init(runID: run, step: 0, sequence: 0, payload: .structuredPart(part, context: context)),
            .init(runID: run, step: 0, sequence: 1, payload: .structuredPart(changed, context: context))
        ])
        #expect(throws: HanlinChatStructuredPartError.conflictingReplay) { try conflict.validate() }
        var ordering = HanlinChatStructuredPartSequence()
        #expect(try ordering.admit(part))
        let wrongKind = try HanlinChatStructuredPart(messageID: message, partID: partID, sequence: 1,
            payload: .a2uiMessage(protocolVersion: "v0.9", json: Data("{}".utf8)))
        #expect(throws: HanlinChatStructuredPartError.conflictingReplay) { try ordering.admit(wrongKind) }
    }
}
