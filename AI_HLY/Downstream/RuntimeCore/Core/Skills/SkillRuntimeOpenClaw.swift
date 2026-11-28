import Foundation
import HanlinSkillFormat

/// Pinned, unchanged OpenClaw policy in the ORIGINAL embedded Node engine.
/// This diagnostic does not execute a Skill, install anything, or grant approval.
enum SkillRuntimeOpenClaw {
    static let artifactSHA256 = "d6cc833943108245a2a68fc85ff4d67bf50719ade36e52fc63c784afedf9d565"

    struct InvocationPolicy: Codable, Hashable, Sendable {
        let userInvocable: Bool
        let disableModelInvocation: Bool
    }

    struct InstallHint: Codable, Hashable, Sendable {
        let kind: String
        let id: String?
        let label: String?
        let bins: [String]?
        let os: [String]?
        let formula: String?
        let package: String?
        let module: String?
        let url: String?
        let sha256: String?
        let archive: String?
        let extract: Bool?
        let stripComponents: Double?
        let targetDir: String?
        var target: String { package ?? formula ?? module ?? url ?? "" }
    }

    struct Report: Decodable, Sendable {
        struct Result: Decodable, Sendable {
            let selected: Bool
            let included: Bool
            let optimisticIncluded: Bool
            let eligible: Bool
        }
        let metadataStatus: String
        let declaredMetadata: Bool
        let rawUpstreamResult: Result?
        let known: Bool
        let invocation: InvocationPolicy
        let installHints: [InstallHint]
        let unobserved: [String]
        let factScope: String
        let executionVerified: Bool
    }

    static func requiresPolicy(_ document: SkillMarkdownDocument) -> Bool {
        guard let metadata = document.metadata else { return false }
        return metadata.mapping == nil || metadata["openclaw"] != nil || metadata["clawdbot"] != nil
    }

    static func hasInvocationMetadata(_ document: SkillMarkdownDocument) -> Bool {
        document.root["user-invocable"] != nil || document.root["disable-model-invocation"] != nil
    }

    /// Typed projection only. The original parser/policy decides semantic support.
    static func supportsRequirementsInput(_ document: SkillMarkdownDocument) -> Bool {
        (try? SkillOpenClawProjection.input(document, enabled: true, bins: [:])) != nil
    }

    static func inspect(_ document: SkillMarkdownDocument, enabled: Bool = true) async throws -> Report? {
        guard requiresPolicy(document) || hasInvocationMetadata(document) else { return nil }
        return try await inspectPolicies([document], enabled: [enabled]).first
    }

    static func inspectPolicies(_ documents: [SkillMarkdownDocument], enabled: [Bool]) async throws -> [Report] {
        guard documents.count == enabled.count else { throw RuntimeCoreError.invalidDependencyManifest }
        guard !documents.isEmpty else { return [] }
        // SKILL_ID uses the original imported-Skill environment boundary. Shared
        // Keychain/provider values never establish facts for an imported Skill.
        _ = try await AppRuntimeCore.shared.ensureStarted(.node)
        let snapshots = await AppRuntimeCore.shared.snapshots()
        var bins: [String: Bool] = [:]
        for (name, kind) in [("node", RuntimeKind.node), ("python3", .localPython)] {
            if let value = snapshots.first(where: { $0.kind == kind }), [.ready, .executing].contains(value.state) {
                bins[name] = true
            }
        }
        let payload = zip(documents, enabled).map { document, enabled in
            (try? SkillOpenClawProjection.input(document, enabled: enabled, bins: bins)) ??
                .init(name: document.name, enabled: enabled, metadataPresence: "unsupported", frontmatter: [:], bins: bins)
        }
        let results: [Report] = try await execute(payload: JSONEncoder().encode(payload),
            skillID: "hanlin-policy-inspection",
            expression: "input.map(value => probeOriginalPolicy(original, value))")
        guard results.count == documents.count, results.allSatisfy({ $0.factScope == "native" && !$0.executionVerified }) else {
            throw RuntimeCoreError.invalidRequest("Original policy diagnostic returned an invalid scope")
        }
        return results
    }

    /// Called for an explicit chat/Skill action, never while rendering a passive plan.
    /// The same original policy normalizer handles both user and model visibility.
    static func invocationPolicies(_ documents: [SkillMarkdownDocument]) async throws -> [InvocationPolicy] {
        guard !documents.isEmpty else { return [] }
        let frontmatter = try documents.map { try SkillOpenClawProjection.invocationFrontmatter($0) }
        return try await execute(payload: JSONEncoder().encode(frontmatter),
            skillID: "hanlin-policy-inspection",
            expression: "input.map(frontmatter => original.resolveSkillInvocationPolicy(frontmatter))")
    }

    private static func execute<Result: Decodable & Sendable>(payload: Data, skillID: String,
                                                               expression: String) async throws -> Result {
        guard payload.count <= 2 * 1_048_576 else { throw RuntimeCoreError.invalidRequest("Skill policy input exceeds its byte budget") }
        let workspace = FileManager.default.temporaryDirectory.appending(path: "openclaw-policy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        for (resource, target, expected) in [
            ("hanlin_openclaw_policy", "policy.mjs", artifactSHA256),
            ("hanlin_openclaw_policy_probe", "policy-probe.mjs", SkillOpenClawProjection.probeSHA256)
        ] {
            guard let url = HanlinApplicationResources.bundle.url(forResource: resource, withExtension: "mjs") else {
                throw RuntimeCoreError.invalidRequest("Original OpenClaw policy artifact missing")
            }
            let bytes = try Data(contentsOf: url)
            guard SkillRuntimeRequirements.digest(bytes) == expected else {
                throw RuntimeCoreError.invalidRequest("Original OpenClaw policy provenance changed")
            }
            try bytes.write(to: workspace.appending(path: target), options: .atomic)
        }
        let literal = String(decoding: try JSONEncoder().encode(payload.base64EncodedString()), as: UTF8.self)
        let policyURL = String(decoding: try JSONEncoder().encode(workspace.appending(path: "policy.mjs").absoluteString), as: UTF8.self)
        let probeURL = String(decoding: try JSONEncoder().encode(workspace.appending(path: "policy-probe.mjs").absoluteString), as: UTF8.self)
        let source = """
        import * as original from \(policyURL);
        import { probeOriginalPolicy } from \(probeURL);
        const input = JSON.parse(Buffer.from(\(literal), 'base64').toString('utf8'));
        console.log(JSON.stringify(\(expression)));
        """
        let result = try await AppRuntimeCore.shared.node.executeJavaScript(
            .init(source: source, workspace: workspace, environment: ["SKILL_ID": skillID]), moduleKind: "esm")
        try Task.checkCancellation()
        guard result.exitCode == 0, !result.wasCancelled, !result.didTimeOut else {
            throw RuntimeCoreError.runtimeFailure("Original OpenClaw policy inspection failed")
        }
        return try JSONDecoder().decode(Result.self, from: Data(result.stdout.utf8))
    }
}
