import Foundation

/// Coordinates Agent run lifecycle, active producer task ownership,
/// cancellation, and run-scoped identity isolation.
/// Prevents cross-run races, ghost tool executions, and ensures a superseded
/// or cancelled run cannot mutate state or diagnostics for a subsequent run.
@MainActor
final class AgentRunLifecycleCoordinator {
    static let shared = AgentRunLifecycleCoordinator()

    struct RunAdmission: Equatable, Sendable {
        fileprivate let runID: UUID
        fileprivate let generation: UUID
    }

    private var latestAdmission: RunAdmission?
    private(set) var activeRunID: UUID?
    private var activeProducerTask: Task<Void, Never>?
    private var activeRecorder: AgentDiagnosticsRecorder?
    private let completeCancelledRecorder: @Sendable (AgentDiagnosticsRecorder) async -> Void

    init(completeCancelledRecorder: @escaping @Sendable (AgentDiagnosticsRecorder) async -> Void = {
        await $0.complete(status: "cancelled")
    }) { self.completeCancelledRecorder = completeCancelledRecorder }

    /// Reserve global request order and request cancellation before a manager awaits its old writer.
    /// Retain the registered producer, recorder, and identity until the original completion paths.
    func reserveRunAdmission(runID: UUID) -> RunAdmission? {
        guard !Task.isCancelled else { return nil }
        let admission = replaceRunAdmission(runID: runID)
        activeProducerTask?.cancel()
        return admission
    }

    private func replaceRunAdmission(runID: UUID) -> RunAdmission {
        let admission = RunAdmission(runID: runID, generation: UUID())
        latestAdmission = admission
        return admission
    }

    func isCurrentAdmission(_ admission: RunAdmission) -> Bool {
        latestAdmission == admission
    }

    private func revokeRunAdmission(runID: UUID?) {
        if runID == nil || latestAdmission?.runID == runID { latestAdmission = nil }
    }

    /// Reject a superseded reservation before any task/recorder mutation, then retain
    /// the original cancellation and recorder-completion ordering.
    func beginRun(admission: RunAdmission, recorder: AgentDiagnosticsRecorder?) async -> Bool {
        guard !Task.isCancelled, isCurrentAdmission(admission) else { return false }
        let oldRecorder = activeRecorder
        if let oldTask = activeProducerTask {
            oldTask.cancel()
            activeProducerTask = nil
        }
        activeRunID = admission.runID
        activeRecorder = recorder
        if let oldRecorder, oldRecorder !== recorder {
            await completeCancelledRecorder(oldRecorder)
        }
        return !Task.isCancelled && isCurrentAdmission(admission) && activeRunID == admission.runID
    }

    /// Begins a new Agent run, cancelling and superseding any existing run.
    func beginRun(runID: UUID, recorder: AgentDiagnosticsRecorder?) async {
        _ = replaceRunAdmission(runID: runID)
        let oldRecorder = activeRecorder
        if let oldTask = activeProducerTask {
            oldTask.cancel()
            activeProducerTask = nil
        }
        activeRunID = runID
        activeRecorder = recorder
        if let oldRecorder, oldRecorder !== recorder {
            await completeCancelledRecorder(oldRecorder)
        }
    }

    /// Synchronous overload for beginRun.
    func beginRun(runID: UUID, recorder: AgentDiagnosticsRecorder?) {
        _ = replaceRunAdmission(runID: runID)
        if let oldTask = activeProducerTask {
            oldTask.cancel()
            activeProducerTask = nil
        }
        if let oldRecorder = activeRecorder, oldRecorder !== recorder {
            Task {
                await completeCancelledRecorder(oldRecorder)
            }
        }
        activeRunID = runID
        activeRecorder = recorder
    }

    /// Recorder creation can suspend. A late initialization belongs only to its
    /// original run and cannot begin that cancelled run a second time.
    @discardableResult
    func attachRecorder(_ recorder: AgentDiagnosticsRecorder?, for runID: UUID) -> Bool {
        guard activeRunID == runID else { return false }
        activeRecorder = recorder
        return true
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
        revokeRunAdmission(runID: runID)
        if let runID, activeRunID != runID {
            return
        }
        activeProducerTask?.cancel()
        activeProducerTask = nil
        let recorder = activeRecorder
        activeRunID = nil
        activeRecorder = nil
        if let recorder { await completeCancelledRecorder(recorder) }
    }

    /// Cancels the specified run, or the currently active run if runID is nil (sync).
    func cancelRun(runID: UUID? = nil) {
        revokeRunAdmission(runID: runID)
        if let runID, activeRunID != runID {
            return
        }
        activeProducerTask?.cancel()
        activeProducerTask = nil
        if let recorder = activeRecorder {
            Task {
                await completeCancelledRecorder(recorder)
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
        revokeRunAdmission(runID: runID)
        activeProducerTask = nil
        activeRunID = nil
        activeRecorder = nil
    }
}
