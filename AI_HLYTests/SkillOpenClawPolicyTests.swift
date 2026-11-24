import Foundation
import HanlinSkillFormat
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Original OpenClaw policy through the existing app runtime", .serialized)
@MainActor
struct SkillOpenClawPolicyTests {
    @Test func originalPolicyRunsInTheActualEmbeddedNode() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "original-policy-native-" + UUID().uuidString)
        let generated = root.appending(path: "generated")
        let tests = root.appending(path: "Tests")
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (resource, ext, target) in [
            ("hanlin_openclaw_policy", "mjs", generated.appending(path: "policy.mjs")),
            ("hanlin_openclaw_policy_probe", "mjs", root.appending(path: "policy-probe.mjs")),
            ("hanlin_openclaw_policy_native_probe", "mjs", root.appending(path: "native-policy-probe.mjs")),
            ("hanlin_openclaw_policy_native_contract", "mjs", generated.appending(path: "native-policy-contract.mjs")),
            ("hanlin_openclaw_policy_provenance", "json", generated.appending(path: "policy-provenance.json")),
            ("hanlin_openclaw_policy_upstream_tests", "mjs", generated.appending(path: "upstream-policy-tests.mjs")),
            ("hanlin_openclaw_policy_test_selection", "json", generated.appending(path: "policy-original-test-selection.json")),
            ("hanlin_openclaw_policy_upstream_shim", "mjs", tests.appending(path: "policy-upstream-shim.mjs"))
        ] {
            let source = try #require(Bundle.main.url(forResource: resource, withExtension: ext))
            try Data(contentsOf: source).write(to: target)
        }
        let challenge = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let output = root.appending(path: "result.json")
        let result = try await AppRuntimeCore.shared.node.executeCLI(entryPoint: root.appending(path: "native-policy-probe.mjs"),
            arguments: [challenge], workspace: root,
            environment: ["SKILL_ID": "original-policy-native-test", "HANLIN_OPENCLAW_POLICY_RESULT": output.path])
        #expect(result.exitCode == 0 && !result.wasCancelled && !result.didTimeOut, "\(result.stderr)")
        let report = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(report["challenge"] as? String == challenge && report["ok"] as? Bool == true)
        #expect(report["node"] as? String == "24.5.0")
        #expect(report["upstreamCases"] as? Int == 28)
        let cases = try #require(report["cases"] as? [[String: Any]])
        #expect(cases.count == 11 && cases.allSatisfy { $0["status"] as? String == "EXECUTED_PASS" })
        let offline = try #require(report["offlinePolicyBoundary"] as? [String: Any])
        #expect(offline["status"] as? String == "EXECUTED_PASS")
        #expect(offline["installedBeforePolicyImport"] as? Bool == true)
        #expect(offline["selfChecksPassed"] as? Int == 6)
        #expect(offline["networkAttempts"] as? Int == 0 && offline["installerAttempts"] as? Int == 0
            && offline["processLaunchAttempts"] as? Int == 0)
        #expect(offline["restored"] as? Bool == true)
        let identity = try #require(report["artifactIdentity"] as? [String: Any])
        #expect(identity["artifactSHA256"] as? String == SkillRuntimeOpenClaw.artifactSHA256)
        print("OPENCLAW_ORIGINAL_POLICY_NATIVE " + String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
    }

    @Test func actualYamsMetadataKeepsOriginalInstallAndDynamicEnablementPolicy() async throws {
        let source = Data("""
        ---
        name: native-policy-fixture
        description: Original policy through Yams and Node
        user-invocable: false
        disable-model-invocation: true
        metadata:
          openclaw:
            requires:
              bins: node
            install:
              - kind: node
                package: "file:../rejected"
              - kind: node
                package: "@scope/fixture@1.2.3"
        ---
        Existing Skill instructions.
        """.utf8)
        let document = try SkillDocumentParser.parse(source)
        let enabledReport = try await SkillRuntimeOpenClaw.inspect(document, enabled: true)
        let enabled = try #require(enabledReport)
        #expect(enabled.metadataStatus == "supported" && enabled.known && !enabled.executionVerified)
        #expect(enabled.rawUpstreamResult?.eligible == true)
        #expect(enabled.installHints.map(\.target) == ["@scope/fixture@1.2.3"])
        #expect(!enabled.invocation.userInvocable && enabled.invocation.disableModelInvocation)
        let disabledReport = try await SkillRuntimeOpenClaw.inspect(document, enabled: false)
        let disabled = try #require(disabledReport)
        #expect(disabled.known && disabled.rawUpstreamResult?.eligible == false)
        #expect(document.originalSource == source, "Inspection must not rewrite imported metadata")
    }

    @Test func originalInvocationFlagsAndDefaultAreResolvedInOneNativeBatch() async throws {
        let make = { (flags: String) throws in
            try SkillDocumentParser.parse(Data(("---\nname: invocation-fixture\ndescription: Original invocation policy\n" + flags + "---\nInstructions\n").utf8))
        }
        let documents = try [make("user-invocable: false\ndisable-model-invocation: true\n"), make("")]
        let policies = try await SkillRuntimeOpenClaw.invocationPolicies(documents)
        #expect(policies == [.init(userInvocable: false, disableModelInvocation: true),
                             .init(userInvocable: true, disableModelInvocation: false)])
    }

    @Test func currentOriginalPolicyControlsLoadReadAndActualSDKContinuation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "policy-catalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillStore(rootDirectoryURL: root.appending(path: "store"), onCatalogChange: {})
        let catalog = HanlinSkillCatalog()
        let id = try HanlinSkillID(validating: "policy-" + UUID().uuidString.lowercased())
        let guide = root.appending(path: "guide.md")
        let nonce = UUID().uuidString
        try Data(("CURRENT_RESOURCE_" + nonce).utf8).write(to: guide)
        let instructions = "CURRENT_INSTRUCTIONS_" + nonce
        func publish(modelDisabled: Bool, userInvocable: Bool) throws {
            let markdown = """
            ---
            name: \(id.rawValue)
            description: Current policy at the real SDK boundary
            user-invocable: \(userInvocable)
            disable-model-invocation: \(modelDisabled)
            metadata:
              openclaw:
                requires:
                  bins: node
            ---
            \(instructions)
            """
            let document = try SkillDocumentParser.parse(Data(markdown.utf8))
            let descriptor = try HanlinSkillDescriptor(id: id, title: "Original Policy",
                summary: "Current invocation metadata", instructions: .inline(instructions),
                preferredToolIDs: ["independently_discovered"])
            catalog.register(descriptor: descriptor, markdownDocument: document,
                resourceResolver: { $0 == "guide.md" ? guide : nil })
        }
        try publish(modelDisabled: true, userInvocable: true)
        let session = AssistantCapabilitySession(isTemporaryChat: true)
        let args = #"{"skill_id":""# + id.rawValue + #""}"#
        let hidden = await catalog.modelVisibleSkills(store: store)
        #expect(hidden.isEmpty)
        #expect(try await catalog.permitsInvocation(id, source: .user, store: store))
        let denied = await LoadSkillTool.execute(argumentsJSON: args, session: session, catalog: catalog, store: store)
        #expect(denied.hasPrefix("Error:") && !session.isSkillLoaded(id))
        let missing = await LoadSkillTool.execute(argumentsJSON: #"{"skill_id":"missing"}"#,
            session: session, catalog: catalog, store: store)
        #expect(!missing.contains(id.rawValue), "Model-hidden metadata must not leak through discovery suggestions")

        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [])
        var executionCount = 0
        let executors = AssistantToolBridge.Executors(
            executeNative: { _, _, _, _ in
                executionCount += 1
                return NativeToolResult(modelText: "Not invoked by policy inspection", outcome: .failed)
            },
            executeScripting: { _, _ in
                executionCount += 1
                return NativeToolResult(modelText: "Not invoked by policy inspection", outcome: .failed)
            })
        let prepared = AssistantToolBridge.PreparedTools(authority: authority, executors: executors)
        let selectedDescriptor = HanlinComposerCapabilityDescriptor(
            reference: .init(kind: .skill, sourceID: "hanlin.skills", capabilityID: id.rawValue),
            title: "Explicit original policy")
        let selectedAttachment = selectedDescriptor.makeAttachment()
        let selectedSession = AssistantCapabilitySession(isTemporaryChat: true,
            capabilityAttachments: [selectedAttachment])
        try await selectedSession.prepareExplicitSelections(using: prepared, catalog: catalog, store: store,
            capabilityCatalog: [selectedDescriptor])
        #expect(selectedSession.isSkillLoaded(id))
        #expect(selectedSession.explicitlySelectedSkillIDs == [id])
        #expect(executionCount == 0, "Attaching a Skill loads instructions without executing a tool")

        let selectedAdapter = HanlinAISDKToolAdapter(session: selectedSession,
            preparedTools: prepared, catalog: catalog, skillStore: store)
        let selectedFirstStep = await selectedAdapter.prepareStep(stepNumber: 0)
        #expect(selectedFirstStep.loadedSkillIDs == [id.rawValue])
        #expect(selectedFirstStep.loadedSkillInstructions.contains(instructions),
                "A user-invocable Skill must survive the first SDK step even when hidden from model discovery")
        #expect(selectedFirstStep.loadedSkillInstructions.contains { $0.contains(selectedAttachment.id.uuidString) })
        #expect(await catalog.modelVisibleSkills(store: store).isEmpty)
        #expect(try await !catalog.permitsInvocation(id, source: .model, store: store))
        let readArgs = #"{"skill_id":""# + id.rawValue + #"","relative_path":"guide.md"}"#
        let selectedRead = await ReadSkillResourceTool.execute(argumentsJSON: readArgs,
            session: selectedSession, catalog: catalog, store: store)
        #expect(selectedRead.contains("CURRENT_RESOURCE_" + nonce),
                "Resources inherit the explicit selection's .user invocation source")
        #expect(!session.isSkillLoaded(id) && session.explicitlySelectedSkillIDs.isEmpty,
                "Explicit loading must not leak into another capability session")

        // Revoke only user invocation, without changing the Store's enabled bit.
        // Resource access must re-evaluate policy before the next SDK step prunes it.
        try publish(modelDisabled: true, userInvocable: false)
        let revokedRead = await ReadSkillResourceTool.execute(argumentsJSON: readArgs,
            session: selectedSession, catalog: catalog, store: store)
        #expect(revokedRead.hasPrefix("Error:") && !revokedRead.contains(nonce))
        let selectedAfterRevocation = await selectedAdapter.prepareStep(stepNumber: 1)
        #expect(selectedAfterRevocation.loadedSkillIDs.isEmpty)
        #expect(!selectedAfterRevocation.loadedSkillInstructions.contains(instructions))
        #expect(selectedSession.explicitlySelectedSkillIDs.isEmpty && selectedSession.activeSkillToolHints.isEmpty)
        let revokedSelection = AssistantCapabilitySession(isTemporaryChat: true,
            capabilityAttachments: [selectedAttachment])
        await #expect(throws: HanlinComposerCapabilityError.self) {
            try await revokedSelection.prepareExplicitSelections(using: prepared, catalog: catalog, store: store,
                capabilityCatalog: [selectedDescriptor])
        }
        #expect(!revokedSelection.isSkillLoaded(id) && executionCount == 0)

        try publish(modelDisabled: true, userInvocable: true)
        let selectedAfterReenable = await selectedAdapter.prepareStep(stepNumber: 2)
        #expect(selectedAfterReenable.loadedSkillIDs.isEmpty,
                "Re-enabling user invocation cannot revive a previously revoked selection")

        // A source edit must invalidate the original policy, even without a Store revision.
        try publish(modelDisabled: false, userInvocable: false)
        #expect(try await !catalog.permitsInvocation(id, source: .user, store: store))
        let loaded = await LoadSkillTool.execute(argumentsJSON: args, session: session, catalog: catalog, store: store)
        #expect(!loaded.hasPrefix("Error:") && session.isSkillLoaded(id))
        let read = await ReadSkillResourceTool.execute(argumentsJSON: readArgs, session: session, catalog: catalog, store: store)
        #expect(read.contains("CURRENT_RESOURCE_" + nonce))

        let adapter = HanlinAISDKToolAdapter(session: session,
            preparedTools: prepared,
            catalog: catalog, skillStore: store)
        let before = await adapter.prepareStep(stepNumber: 0)
        #expect(before.loadedSkillIDs == [id.rawValue] && before.loadedSkillInstructions == [instructions])
        session.exposeTools(aliases: ["independently_discovered"])
        store.setSkillEnabled(id: id, enabled: false)
        let deniedRead = await ReadSkillResourceTool.execute(argumentsJSON: readArgs, session: session, catalog: catalog, store: store)
        #expect(deniedRead.hasPrefix("Error:") && !deniedRead.contains(nonce))
        let after = await adapter.prepareStep(stepNumber: 1)
        #expect(after.loadedSkillIDs.isEmpty && after.loadedSkillInstructions.isEmpty)
        #expect(session.activeSkillToolHints.isEmpty)
        #expect(session.isToolExposed("independently_discovered"), "Skill metadata must not replace the Tool catalog's authorization")
        store.setSkillEnabled(id: id, enabled: true)
        #expect(try await catalog.permitsInvocation(id, source: .model, store: store))
        #expect(!session.isSkillLoaded(id), "Re-enabling must require a new load instead of reviving stale instructions")
        #expect(executionCount == 0)
    }

    @Test func pruningOneSkillRetainsSharedInstructionsOwnedByAnotherSkill() throws {
        let a = try HanlinSkillID(validating: "owner-a"), b = try HanlinSkillID(validating: "owner-b")
        let session = AssistantCapabilitySession(isTemporaryChat: true)
        session.recordSkillLoaded(id: a, instructionText: "Shared instructions", preferredToolIDs: ["only-a", "shared"])
        session.recordSkillLoaded(id: b, instructionText: "Shared instructions", preferredToolIDs: ["only-b", "shared"])
        session.retainLoadedSkills(allowedIDs: [b])
        #expect(session.loadedSkillIDs == [b])
        #expect(session.loadedSkillInstructions == ["Shared instructions"])
        #expect(session.activeSkillToolHints == ["only-b", "shared"])
        session.reset()
        #expect(session.loadedSkillIDs.isEmpty && session.loadedSkillInstructions.isEmpty && session.activeSkillToolHints.isEmpty)
    }
}
