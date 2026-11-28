import Foundation
import HanlinPlatformContracts
import Testing

@Suite struct ToolApprovalAndPresentationTests {
    @Test func missingPresentationMetadataUsesGenericToolsAndCommonAnimation() throws {
        let legacy = try JSONDecoder().decode(HanlinToolExecutionPresentationDescriptor.self, from: Data("{}".utf8))
        #expect(legacy.resolvedSystemImage == "wrench.and.screwdriver")
        #expect(legacy.resolvedAnimation == .common)
        #expect(HanlinToolExecutionPresentationDescriptor(systemImage: " ").resolvedSystemImage == "wrench.and.screwdriver")
    }

    @Test func explicitMetadataRoundTripsAndOverridesFamilyAnimation() throws {
        let value = HanlinToolExecutionPresentationDescriptor(familyID: .webSearch, systemImage: "map", animation: .execution)
        let decoded = try JSONDecoder().decode(HanlinToolExecutionPresentationDescriptor.self, from: JSONEncoder().encode(value))
        #expect(decoded == value)
        #expect(decoded.resolvedSystemImage == "map")
        #expect(decoded.resolvedAnimation == .execution)
        #expect(HanlinToolExecutionPresentationDescriptor(familyID: .sourceSearch).resolvedAnimation == .search)
        #expect(HanlinToolExecutionPresentationDescriptor(familyID: .codeExecution).resolvedAnimation == .execution)
        #expect(HanlinToolExecutionPresentationDescriptor(familyID: "unknown").resolvedAnimation == .common)
    }

    @Test func unknownAnimationCannotInjectCustomExecutableContent() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HanlinToolExecutionPresentationDescriptor.self, from: Data(#"{"animation":"run-javascript"}"#.utf8))
        }
    }

    @Test func nonSensitiveReadDoesNotRequireBlanketConsent() {
        let read = HanlinToolApprovalDescriptor(requiresApproval: false)
        #expect(!read.requiresConsent(arguments: .object([:]), risk: .read))
        #expect(!read.requiresConsent(arguments: .object([:]), risk: .passive))
        #expect(read.requiresConsent(arguments: .object([:]), risk: .sensitiveRead))
        #expect(read.requiresConsent(arguments: .object([:]), risk: .privileged))
    }

    @Test func mixedManifestExemptsOnlyExactDeclaredReadActions() {
        let policy = HanlinToolApprovalDescriptor(actionParameter: "action", nonSensitiveActions: ["list", "preview"], scopeParameters: ["runtime"])
        for action in ["list", "preview"] {
            #expect(!policy.requiresConsent(arguments: .object(["action": .string(action)]), risk: .write))
        }
        for action in ["install", "uninstall", "call_tool", "LIST", " list", "other"] {
            #expect(policy.requiresConsent(arguments: .object(["action": .string(action)]), risk: .write))
        }
        #expect(policy.requiresConsent(arguments: .object([:]), risk: .write))
        #expect(policy.requiresConsent(arguments: .object(["action": .bool(false)]), risk: .write))
    }

    @Test func optionalPolicyFieldsDecodeSafely() throws {
        let decoded = try JSONDecoder().decode(HanlinToolApprovalDescriptor.self, from: Data("{}".utf8))
        #expect(decoded.requiresApproval)
        #expect(decoded.nonSensitiveActions.isEmpty)
        #expect(decoded.scopeParameters.isEmpty)
        #expect(decoded.requiresConsent(arguments: .object([:]), risk: .read))
    }
}
