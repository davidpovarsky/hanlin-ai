import Foundation

/// Coordinates Agent run lifecycle, active producer task ownership,
/// cancellation, and run-scoped identity isolation.
/// Prevents cross-run races, ghost tool executions, and ensures a superseded
/// or cancelled run cannot mutate state or diagnostics for a subsequent run.
@MainActor
final class AgentRunLifecycleCoordinator {
    static let shared = AgentRunLifecycleCoordinator()

    private(set) var activeRunID: UUID?
    private var activeProducerTask: Task<Void, Never>?
    private var activeRecorder: AgentDiagnosticsRecorder?

    init() {}

    /// Begins a new Agent run, cancelling and superseding any existing run.
    func beginRun(runID: UUID, recorder: AgentDiagnosticsRecorder?) async {
        if let oldTask = activeProducerTask {
            oldTask.cancel()
            activeProducerTask = nil
        }
        if let oldRecorder = activeRecorder, oldRecorder !== recorder {
            await oldRecorder.complete(status: "cancelled")
        }
        activeRunID = runID
        activeRecorder = recorder
    }

    /// Synchronous overload for beginRun.
    func beginRun(runID: UUID, recorder: AgentDiagnosticsRecorder?) {
        if let oldTask = activeProducerTask {
            oldTask.cancel()
            activeProducerTask = nil
        }
        if let oldRecorder = activeRecorder, oldRecorder !== recorder {
            Task {
                await oldRecorder.complete(status: "cancelled")
            }
        }
        activeRunID = runID
        activeRecorder = recorder
    }

    /// Attaches the root producer task for the active run.
    func attachProducerTask(_ task: Task<Void, Never>, for runID: UUID) {
        guard activeRunID == runID else {
            task.cancel()
            return
        }
        activeProducerTask = task
    }

    /// Cancels the specified run, or the currently active run if runID is nil (async).
    func cancelRun(runID: UUID? = nil) async {
        if let runID, activeRunID != runID {
            return
        }
        activeProducerTask?.cancel()
        activeProducerTask = nil
        if let recorder = activeRecorder {
            await recorder.complete(status: "cancelled")
        }
        activeRunID = nil
        activeRecorder = nil
    }

    /// Cancels the specified run, or the currently active run if runID is nil (sync).
    func cancelRun(runID: UUID? = nil) {
        if let runID, activeRunID != runID {
            return
        }
        activeProducerTask?.cancel()
        activeProducerTask = nil
        if let recorder = activeRecorder {
            Task {
                await recorder.complete(status: "cancelled")
            }
        }
        activeRunID = nil
        activeRecorder = nil
    }

    /// Checks if the given run ID is still the active, non-superseded run.
    func isCurrentRun(_ runID: UUID) -> Bool {
        activeRunID == runID
    }

    /// Cleans up state when a run finishes, only if it is still the active run.
    func finishRun(runID: UUID) {
        guard activeRunID == runID else { return }
        activeProducerTask = nil
        activeRunID = nil
        activeRecorder = nil
    }
}
