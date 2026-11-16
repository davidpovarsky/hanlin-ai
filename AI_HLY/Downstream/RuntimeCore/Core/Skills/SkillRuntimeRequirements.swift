import CryptoKit
import Foundation
import HanlinSkillFormat

/// Projection of immutable Yams nodes and original AST facts into Runtime05.
/// No dependency is installed or imported while projecting these requirements.
enum SkillRuntimeRequirements {
    typealias C = SkillRuntimeContract

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func kind(_ engine: C.EngineID) -> RuntimeKind? {
        switch engine {
        case .node: .node
        case .typeScript: .typeScript
        case .python: .localPython
        case .javaScriptCore: .javaScriptCore
        case .shell: .shell
        default: nil
        }
    }

    static func engine(_ kind: RuntimeKind) -> C.EngineID {
        switch kind {
        case .node: .node
        case .typeScript: .typeScript
        case .localPython: .python
        case .javaScriptCore: .javaScriptCore
        case .shell: .shell
        }
    }

    /// A routing suggestion only; the observed engine and requirements must still pass.
    static func suggestedEngine(path: String) -> C.EngineID? {
        switch (path as NSString).pathExtension.lowercased() {
        case "js", "mjs", "cjs": .node
        case "ts": .typeScript
        case "py": .python
        case "sh", "bash": .shell
        default: nil
        }
    }

    static func action(skillID: String, document: SkillMarkdownDocument, path: String?,
                       bytes: Data, engine: C.EngineID?, arguments: [String],
                       environmentID: String, syntax: SkillSyntaxReport? = nil,
                       openClawKnown: Bool = false, packageFingerprint: String? = nil) throws -> C.Action {
        let sourceHash = packageFingerprint ?? digest(document.originalSource)
        let actionHash = digest(bytes)
        let evidence = C.SourceEvidence(kind: .declared, producer: "HanlinSkillFormat/Yams",
            producerVersion: "6.2.2", sourceID: skillID, sourceVersion: nil,
            sourceFingerprint: sourceHash, observedAt: nil, artifactReference: "SKILL.md")
        var requirements: [C.SkillRequirement] = []
        var complete = document.findings.isEmpty && (path == nil || syntax != nil)
            && SkillRuntimeOpenClaw.supportsRequirementsInput(document)
        func add(_ kind: C.RequirementKind, _ name: String) {
            guard !name.isEmpty else { complete = false; return }
            let key = C.RequirementKey(kind: kind, name: name, versionConstraint: nil)
            if !requirements.contains(where: { $0.key == key }) {
                requirements.append(.init(id: "\(kind.rawValue):\(name)", key: key, evidence: evidence))
            }
        }
        if let engine { add(.engine, engine.rawValue) }
        if engine == .shell { add(.capability, "shell.portable-parser") }
        let metadata = document.metadata?["openclaw"] ?? document.metadata?["clawdbot"]
        let declared = document.root["requires"]
        if metadata != nil {
            add(.capability, "openclaw.requirements")
            complete = complete && openClawKnown
        }
        if let declared {
            guard let mapping = declared.mapping else {
                return .init(id: path ?? "instructions", kind: path == nil ? .instructions : .script,
                    skillID: skillID, sourceFingerprint: sourceHash, actionFingerprint: actionHash,
                    invocationFingerprint: nil, relativePath: path, environmentID: environmentID,
                    engineID: engine, requirements: requirements, requirementsComplete: false)
            }
            for entry in mapping {
                guard let name = entry.key.stringValue, let values = entry.value.sequence,
                      values.allSatisfy({ $0.stringValue != nil }) else { complete = false; continue }
                let kind: C.RequirementKind
                switch name {
                case "bins": kind = .command
                case "npm", "python", "modules": kind = .module
                case "env", "config": kind = .capability
                default: complete = false; continue
                }
                for value in values {
                    if let text = value.stringValue { add(kind, ["env", "config"].contains(name) ? name + ":" + text : text) }
                }
            }
        }
        // OS/always/anyBins require the exact upstream predicate, never flatten to all-bins.
        if declared?["anyBins"] != nil {
            complete = false
        }
        if let syntax {
            complete = complete && syntax.completion == .complete
            for finding in syntax.findings {
                if finding.confidence == .unknown || finding.kind == .unknown { complete = false }
                if let value = finding.value {
                    switch finding.kind {
                    case .moduleReference: add(.module, value)
                    case .command: add(.command, value)
                    case .dependencyDeclaration: add(.unknown, "declared: " + value); complete = false
                    default: break
                    }
                }
            }
        }
        let invocation = try JSONEncoder().encode(arguments)
        return .init(id: path ?? "instructions", kind: path == nil ? .instructions : .script,
            skillID: skillID, sourceFingerprint: sourceHash, actionFingerprint: actionHash,
            invocationFingerprint: digest(invocation), relativePath: path, environmentID: environmentID,
            engineID: engine, requirements: requirements, requirementsComplete: complete)
    }
}
