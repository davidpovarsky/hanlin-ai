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
            "javascriptcoreJobs": "Original synchronous JavaScriptCore keeps complete console output in durable jobs with lossless read pages. Queued jobs can be cancelled. Public Apple APIs cannot safely kill a running context; cancellation/interruption stays pending until natural return and retains late bytes. Explicit deadlines are rejected before execution; use Node workers for interruptible work. No source-size or source-word policy is imposed.",
            "jobs": "Node/Python/TypeScript have durable job IDs and full stdout/stderr artifacts. Execution deadlines are optional. Node/TypeScript cancel managed Workers. Serialized Python jobs retain output/cwd/environment until newly created CPython thread states drain, including daemon/raw threads. Python cancellation is cooperative; untraced threads and blocking native calls must return naturally. Native libraries that schedule future callbacks after detaching all Python thread states need their own lifetime contract. Interrupted jobs are not replayed automatically.",
            "agentSteps": "No default step cap; an explicit caller budget is optional. Completion, user cancellation and actual errors terminate a run.",
            "executionInput": "Original Node execution, TypeScript compilation and lifecycle-plan verification spill large source/argv/environment requests into UUID-owned files with full size/SHA-256 receipts. The Host claims them into the reserved job before parsing or execution; observation/retry cannot replay the ID. The inline threshold is transport routing, not a source-size limit. Engine memory/disk errors still apply; other legacy HTTP/native-API protocol budgets require their own file/stream routes.",
            "typeScriptCompilerJobs": "Original Swift compilation and project builds use managed Node Workers with durable IDs and complete compiler JSON stdout. Stop cancels compiler and execution Workers and prevents a stopped compilation from launching JavaScript. No default compilation deadline or source/argument-count cap is imposed. Compiler versions come from the actual loaded compiler; native integration acceptance remains separately recorded.",
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
