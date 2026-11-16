import Foundation

/// The single eligibility adapter for the original Host runtime-capabilities.mjs
/// schema. It decodes already-observed data; it never starts or contacts Node.
/// Callers must obtain the report through capabilityReportIfLaunched() and bind
/// the actual engine/environment identity, rather than trusting Skill metadata.
enum SkillRuntimeNodeCapabilityAdapter {
    typealias C = SkillRuntimeContract

    enum ObservationError: Error, Equatable {
        case unsupportedSchema, wrongProfile, wrongEngineBinding, unboundIdentity
    }

    private struct Report: Decodable {
        struct Observed: Decodable {
            let node: String
            let pointerCompression: Bool?
            let v8Sandbox: Bool?
            let webAssemblyAvailable: Bool?
            let fetchImplementation: String?
            let builtInModules: [String]?
            let portableShellAdapterVersion: Int?
        }

        let schemaVersion: Int
        let targetProfile: String
        let executionBoundary: String
        let observed: Observed
    }

    static func inspect(report data: Data, binding: C.EngineBinding,
                        observedAt: Date, artifactReference: String?) throws -> C.EngineFacts {
        let report = try JSONDecoder().decode(Report.self, from: data)
        guard report.schemaVersion == 1 else { throw ObservationError.unsupportedSchema }
        guard report.targetProfile == "hanlin-ios-app",
              report.executionBoundary == "same-process-worker-threads" else {
            throw ObservationError.wrongProfile
        }
        guard binding.engineID == .node, !report.observed.node.isEmpty,
              report.observed.node == binding.engineVersion else {
            throw ObservationError.wrongEngineBinding
        }
        guard isSHA256(binding.engineFingerprint), isSHA256(binding.environmentFingerprint),
              !binding.environmentID.isEmpty else { throw ObservationError.unboundIdentity }
        let evidence = C.SourceEvidence(kind: .observed,
            producer: "NodeRuntimeService.capabilityReportIfLaunched/runtime-capabilities.mjs",
            producerVersion: "schema1", sourceID: C.EngineID.node.rawValue,
            sourceVersion: report.observed.node, sourceFingerprint: binding.engineFingerprint,
            observedAt: observedAt, artifactReference: artifactReference)
        var facts: [C.CapabilityFact] = []
        func add(_ kind: C.RequirementKind, _ name: String, _ status: C.FactStatus, version: String? = nil) {
            facts.append(.init(requirement: .init(kind: kind, name: name, versionConstraint: nil),
                               binding: binding, status: status, resolvedVersion: version,
                               resolvedPath: nil, evidence: evidence))
        }
        add(.engine, C.EngineID.node.rawValue, .available, version: report.observed.node)
        if report.observed.portableShellAdapterVersion == 1 {
            add(.capability, "node.portable-shell.original", .available, version: "1")
        }
        for name in Set(report.observed.builtInModules ?? []).sorted() {
            add(.module, name, .available, version: report.observed.node)
            if !name.hasPrefix("node:") { add(.module, "node:" + name, .available, version: report.observed.node) }
        }
        // Namespace presence and compiled configuration are narrow facts. They
        // do not certify WASM bundles, JIT, sandbox isolation or package imports.
        for (name, value) in [
            ("node.webassembly.namespace", report.observed.webAssemblyAvailable),
            ("node.build.pointer-compression", report.observed.pointerCompression),
            ("node.build.v8-sandbox", report.observed.v8Sandbox)
        ] {
            if let value { add(.capability, name, value ? .available : .unsupported) }
        }
        if let transport = report.observed.fetchImplementation,
           ["node-undici", "node-fetch@3.3.2+native-web-api"].contains(transport) {
            add(.capability, "node.fetch.selected-transport", .available, version: transport)
        }
        return .init(engineID: .node, binding: binding, facts: facts)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}
