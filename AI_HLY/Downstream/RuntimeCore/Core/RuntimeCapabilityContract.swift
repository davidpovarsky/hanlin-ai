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
            "jobs": "Node/Python/TypeScript have durable job IDs, full stdout/stderr artifacts and optional explicit deadlines. Serialized Python jobs retain output/cwd/environment until newly created CPython thread states drain, including daemon/raw threads. Cancellation is cooperative; untraced threads and blocking native calls must return naturally. Native libraries that schedule future callbacks after detaching all Python thread states need their own lifetime contract. Interrupted jobs are not replayed automatically.",
            "agentSteps": "No default step cap; an explicit caller budget is optional. Completion, user cancellation and actual errors terminate a run.",
            "authorization": "No per-package Hanlin grants. Real OS permissions, owner disable/stop, session identity, integrity and TLS still apply.",
            "pythonPackages": "Standards-based packaging/resolvelib resolution uses running-interpreter markers and wheel tags, compatible PEP 517 source backends and local sources. Native imports require providers actually registered in the signed app; arbitrary desktop binary compatibility is not implied. Installation commits only after the staged import probe.",
            "nodePackages": "Embedded Node. Package compatibility depends on APIs actually used; desktop child_process/cluster/native addon behavior is not implied.",
            "cliCommands": "hanlin:runtime runCommand exposes finite file-backed Node/Python/linked BSD adapters through the same existing engines and job journals. Actual exit codes, execution IDs and full output paths are returned. Original npm lifecycle/pre/main/post execution shares that route. Owning-parent cancellation is supported; per-command process signals, OS spawn, PID, TTY and IPC are not emulated. Persistent MCP servers have no inherited chat command port; whole POSIX contexts need an explicitly configured owner server.",
            "shell": "Full stdout/stderr are durable job artifacts with lossless read pages. Structured argv and linked ios_system command strings support native pipes/redirection. Queued commands can be cancelled; running native commands currently finish naturally and do not support per-command deadlines. Full Bash compatibility is not implied.",
            "wasm": "NOT_VERIFIED on the embedded iOS engine; no JIT availability is assumed.",
            "unicodePropertyEscapes": "The current native Node build cannot parse general Unicode property escapes. The pinned Yarn parser uses equivalent Unicode 16 literal character classes; that dependency patch does not add property syntax or ICU to the engine.",
            "fetch": "Query live Node capabilities for the selected transport. Native Undici is selected only when WebAssembly is actually available; the no-WASM fallback explicitly rejects a supplied dispatcher. TLS remains verified. Current-bundle SRI/proxy/class/stream native acceptance is required separately.",
            "background": "Original foreground user-started agent runs request CPU/network BGContinuedProcessingTask continuation. Admission is optional and never gates foreground work. Progress counts actual output with an unknown total. OS expiry or native Cancel interrupts the owning run and its jobs; partial output is retained without side-effect replay. Running linked C calls may finish before cancellation settles. App termination is recovered as interrupted; uninterrupted completion is not guaranteed. Physical background acceptance remains NOT_VERIFIED."
        ]
    }
}
