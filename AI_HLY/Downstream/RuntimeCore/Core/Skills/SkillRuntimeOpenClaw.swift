import Foundation
import HanlinSkillFormat

/// The pinned original requirements predicate, not OpenClaw's full selection/install policy.
enum SkillRuntimeOpenClaw {
    struct Report: Decodable, Sendable {
        struct Result: Decodable, Sendable { let eligible: Bool }
        let rawUpstreamResult: Result
        let unobserved: [String]
        var known: Bool { unobserved.isEmpty }
    }

    static func metadata(_ document: SkillMarkdownDocument) -> SkillMetadataNode? {
        document.metadata?["openclaw"] ?? document.metadata?["clawdbot"]
    }

    static func inspect(_ document: SkillMarkdownDocument) async throws -> Report? {
        guard let metadata = metadata(document) else { return nil }
        guard let url = Bundle.main.url(forResource: "hanlin_openclaw_requirements", withExtension: "js") else {
            throw RuntimeCoreError.invalidRequest("Original OpenClaw requirements artifact missing")
        }
        let artifact = try Data(contentsOf: url)
        guard SkillRuntimeRequirements.digest(artifact) == "e492e2d611bb42e15b26411ab055afce87add4eea317789521c6fe36cc28970c" else {
            throw RuntimeCoreError.invalidRequest("Original OpenClaw requirements provenance changed")
        }
        let snapshots = await AppRuntimeCore.shared.snapshots()
        var bins: [String: Bool] = [:]
        for (name, kind) in [("node", RuntimeKind.node), ("python3", .localPython)] {
            if let value = snapshots.first(where: { $0.kind == kind }), [.ready, .executing].contains(value.state) {
                bins[name] = true
            }
        }
        let payload = try JSONSerialization.data(withJSONObject: ["metadata": try json(metadata), "bins": bins])
        let literal = String(decoding: try JSONEncoder().encode(payload.base64EncodedString()), as: UTF8.self)
        let source = String(decoding: artifact, as: UTF8.self) + """

        const input=JSON.parse(Buffer.from(\(literal),'base64').toString('utf8'));
        const unobserved=[];
        const has=(kind,key)=>{if(kind==='bins'&&Object.hasOwn(input.bins,key))return input.bins[key];unobserved.push(kind+':'+key);return false;};
        const rawUpstreamResult=HanlinOpenClawOriginalRequirements.evaluateRequirementsFromMetadataWithRemote({
          metadata:input.metadata,always:input.metadata.always===true,localPlatform:process.platform,
          hasLocalBin:key=>has('bins',key),isEnvSatisfied:key=>has('env',key),isConfigSatisfied:key=>has('config',key)});
        console.log(JSON.stringify({rawUpstreamResult,unobserved}));
        """
        let workspace = FileManager.default.temporaryDirectory.appending(path: "openclaw-analysis-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let result = try await AppRuntimeCore.shared.node.executeJavaScript(.init(source: source, workspace: workspace))
        try Task.checkCancellation()
        guard result.exitCode == 0, !result.wasCancelled else { throw RuntimeCoreError.runtimeFailure("OpenClaw requirements inspection failed") }
        return try JSONDecoder().decode(Report.self, from: Data(result.stdout.utf8))
    }

    private static func json(_ node: SkillMetadataNode) throws -> Any {
        if let value = node.stringValue { return value }
        if let value = node.booleanValue { return value }
        if let sequence = node.sequence { return try sequence.map(json) }
        if let entries = node.mapping {
            var result: [String: Any] = [:]
            for entry in entries {
                guard let key = entry.key.stringValue, result[key] == nil else { throw RuntimeCoreError.invalidDependencyManifest }
                result[key] = try json(entry.value)
            }
            return result
        }
        throw RuntimeCoreError.invalidDependencyManifest
    }
}
