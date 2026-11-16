import Foundation

/// Passive adapter over the ORIGINAL engine snapshots; inspecting never starts an engine.
struct SkillRuntimeFactsProvider: SkillRuntimeCapabilityProvider {
    typealias C = SkillRuntimeContract
    let engineID: C.EngineID

    func snapshot(environmentID: String) async -> C.EngineFacts {
        guard let kind = SkillRuntimeRequirements.kind(engineID),
              let snapshot = await AppRuntimeCore.shared.snapshots().first(where: { $0.kind == kind }),
              [.ready, .executing].contains(snapshot.state),
              let version = snapshot.version, let observedAt = snapshot.lastHealthCheck else {
            return .init(engineID: engineID, binding: nil, facts: [])
        }
        // Engine source identity is the actually installed, pinned runtime manifest plus the
        // version observed from its live adapter. Environment changes invalidate prior tests.
        let manifest = Bundle.main.url(forResource: "RuntimeManifest", withExtension: "json")
        guard let manifest, let manifestBytes = try? Data(contentsOf: manifest) else {
            return .init(engineID: engineID, binding: nil, facts: [])
        }
        var identity = manifestBytes
        guard let installedCode = try? await SkillRuntimeInstalledIdentity.shared.fingerprint() else {
            return .init(engineID: engineID, binding: nil, facts: [])
        }
        identity.append(contentsOf: installedCode.utf8)
        identity.append(contentsOf: (engineID.rawValue + ":" + version + ":" + (snapshot.source ?? "")).utf8)
        var environment = Data(environmentID.utf8)
        let layout = RuntimeFileLayout.default
        for url in [layout.environmentRegistry, layout.nodeGlobalPackages.appending(path: "package-lock.json"),
                    layout.registry.appending(path: "PythonPackages.json")] {
            if let bytes = try? Data(contentsOf: url) { environment.append(bytes) }
        }
        let binding = C.EngineBinding(engineID: engineID, engineVersion: version,
            engineFingerprint: SkillRuntimeRequirements.digest(identity), environmentID: environmentID,
            environmentFingerprint: SkillRuntimeRequirements.digest(environment))
        let evidence = C.SourceEvidence(kind: .observed, producer: "AppRuntimeCore.snapshot",
            producerVersion: "1", sourceID: engineID.rawValue, sourceVersion: version,
            sourceFingerprint: binding.engineFingerprint, observedAt: observedAt, artifactReference: nil)
        var facts = [C.CapabilityFact(requirement: .init(kind: .engine, name: engineID.rawValue, versionConstraint: nil),
            binding: binding, status: .available, resolvedVersion: version, resolvedPath: nil, evidence: evidence)]
        if engineID == .node, let report = try? await AppRuntimeCore.shared.node.capabilityReportIfLaunched(),
           let bytes = try? JSONEncoder().encode(report),
           let observed = try? SkillRuntimeNodeCapabilityAdapter.inspect(report: bytes, binding: binding,
                observedAt: .now, artifactReference: nil) {
            facts = observed.facts
        }
        if engineID == .python {
            for name in await AppRuntimeCore.shared.python.observedSkillAnalysisModules {
                facts.append(.init(requirement: .init(kind: .module, name: name, versionConstraint: nil),
                    binding: binding, status: .available, resolvedVersion: version, resolvedPath: nil,
                    evidence: .init(kind: .observed, producer: "PythonRuntimeService.trustedAnalysisImports",
                        producerVersion: "1", sourceID: engineID.rawValue, sourceVersion: version,
                        sourceFingerprint: binding.engineFingerprint, observedAt: .now, artifactReference: nil)))
            }
        }
        if engineID == .typeScript,
           let nodeSnapshot = await AppRuntimeCore.shared.snapshots().first(where: { $0.kind == .node }),
           let nodeVersion = nodeSnapshot.version,
           let report = try? await AppRuntimeCore.shared.node.capabilityReportIfLaunched(),
           let bytes = try? JSONEncoder().encode(report) {
            let nodeBinding = C.EngineBinding(engineID: .node, engineVersion: nodeVersion,
                engineFingerprint: binding.engineFingerprint, environmentID: environmentID,
                environmentFingerprint: binding.environmentFingerprint)
            if let observed = try? SkillRuntimeNodeCapabilityAdapter.inspect(report: bytes, binding: nodeBinding,
                observedAt: .now, artifactReference: nil) {
                for fact in observed.facts where fact.requirement.kind == .module {
                    facts.append(.init(requirement: fact.requirement, binding: binding, status: fact.status,
                        resolvedVersion: fact.resolvedVersion, resolvedPath: fact.resolvedPath,
                        evidence: .init(kind: .observed, producer: fact.evidence.producer,
                            producerVersion: fact.evidence.producerVersion, sourceID: engineID.rawValue,
                            sourceVersion: version, sourceFingerprint: binding.engineFingerprint,
                            observedAt: .now, artifactReference: nil)))
                }
            }
        }
        if engineID == .shell,
           let diagnostics = try? await AppRuntimeCore.shared.shell.commandDependencyDiagnostics() {
            for (name, diagnostic) in diagnostics {
                facts.append(.init(requirement: .init(kind: .command, name: name, versionConstraint: nil),
                    binding: binding, status: diagnostic.isAvailable ? .available : .missing,
                    resolvedVersion: nil, resolvedPath: diagnostic.framework + "/" + diagnostic.symbol, evidence: evidence))
            }
        }
        if engineID == .shell,
           let node = await AppRuntimeCore.shared.snapshots().first(where: { $0.kind == .node }),
           [.ready, .executing].contains(node.state), let nodeVersion = node.version,
           let report = try? await AppRuntimeCore.shared.node.capabilityReportIfLaunched(),
           let bytes = try? JSONEncoder().encode(report),
           let observed = try? SkillRuntimeNodeCapabilityAdapter.inspect(report: bytes,
                binding: .init(engineID: .node, engineVersion: nodeVersion,
                    engineFingerprint: binding.engineFingerprint, environmentID: environmentID,
                    environmentFingerprint: binding.environmentFingerprint), observedAt: .now, artifactReference: nil),
           observed.facts.contains(where: { $0.requirement.name == "node.portable-shell.original" && $0.status == .available }) {
            facts.append(.init(requirement: .init(kind: .capability, name: "shell.portable-parser", versionConstraint: nil),
                binding: binding, status: .available, resolvedVersion: "1", resolvedPath: nil,
                evidence: .init(kind: .observed, producer: "OriginalYarnPortableShell/Node.capabilityReportIfLaunched",
                    producerVersion: "1", sourceID: engineID.rawValue, sourceVersion: version,
                    sourceFingerprint: binding.engineFingerprint, observedAt: .now, artifactReference: nil)))
        }
        return .init(engineID: engineID, binding: binding, facts: facts)
    }
}
