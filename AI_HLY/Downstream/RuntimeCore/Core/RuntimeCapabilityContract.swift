import Foundation

/// Read-only capability reporting. An installed engine is not necessarily running,
/// and package compatibility is never inferred from an engine's presence.
struct RuntimeCapabilityContract: Codable, Sendable {
    let schemaVersion: Int
    let snapshots: [RuntimeSnapshot]
    let defaultLimits: RuntimeExecutionLimits
    let features: [String: String]

    init(snapshots: [RuntimeSnapshot], defaultLimits: RuntimeExecutionLimits = .init()) {
        schemaVersion = 1
        self.snapshots = snapshots
        self.defaultLimits = defaultLimits
        features = [
            "agentSteps": "No default step cap; an explicit caller budget is optional. Completion, user cancellation and actual errors terminate a run.",
            "authorization": "No per-package Hanlin grants. Real OS permissions, owner disable/stop, session identity, integrity and TLS still apply.",
            "pythonPackages": "Pure-Python wheels supported by the current embedded installer. Source builds, full PEP resolution and signed native-extension loading are not yet verified.",
            "nodePackages": "Embedded Node. Package compatibility depends on APIs actually used; desktop child_process/cluster/native addon behavior is not implied.",
            "shell": "Structured argv; linked ios_system commands only. Command language, pipes and redirection are not yet advertised as implemented.",
            "wasm": "NOT_VERIFIED on the embedded iOS engine; no JIT availability is assumed.",
            "fetch": "TLS and native web classes preserved. SRI and custom Undici dispatcher are not yet supported by the current compatibility path.",
            "background": "iOS may suspend or terminate the app. Uninterrupted background completion is not guaranteed."
        ]
    }
}
