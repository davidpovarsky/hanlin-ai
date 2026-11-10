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
            "jobs": "Node/Python/TypeScript have durable job IDs, full stdout/stderr artifacts and optional explicit deadlines. Native Python cancellation is cooperative and may wait for a blocking C call. Interrupted jobs are not replayed automatically.",
            "agentSteps": "No default step cap; an explicit caller budget is optional. Completion, user cancellation and actual errors terminate a run.",
            "authorization": "No per-package Hanlin grants. Real OS permissions, owner disable/stop, session identity, integrity and TLS still apply.",
            "pythonPackages": "Standards-based packaging/resolvelib resolution uses running-interpreter markers and wheel tags, compatible PEP 517 source backends and local sources. Native imports require providers actually registered in the signed app; arbitrary desktop binary compatibility is not implied. Installation commits only after the staged import probe.",
            "nodePackages": "Embedded Node. Package compatibility depends on APIs actually used; desktop child_process/cluster/native addon behavior is not implied.",
            "cliCommands": "Finite file-backed Node/Python script and verified BSD command adapters use the existing engines and job journals. Portable npm run executes pre/main/post scripts. OS spawn, TTY/IPC and unsupported CLI flags are not emulated; registry dependency lifecycle migration is still incomplete.",
            "shell": "Full stdout/stderr are durable job artifacts with lossless read pages. Structured argv and linked ios_system command strings support native pipes/redirection. Queued commands can be cancelled; running native commands currently finish naturally and do not support per-command deadlines. Full Bash compatibility is not implied.",
            "wasm": "NOT_VERIFIED on the embedded iOS engine; no JIT availability is assumed.",
            "fetch": "TLS and native web classes preserved. SRI and custom Undici dispatcher are not yet supported by the current compatibility path.",
            "background": "iOS may suspend or terminate the app. Uninterrupted background completion is not guaranteed."
        ]
    }
}
