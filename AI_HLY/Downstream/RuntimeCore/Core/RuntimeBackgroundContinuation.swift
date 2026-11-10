import BackgroundTasks
import Foundation
import UIKit

/// Optional OS continuation for an original, foreground, user-started agent run.
/// A denied request never gates foreground work or launches a second operation.
@MainActor
final class RuntimeBackgroundContinuation {
    static let shared = RuntimeBackgroundContinuation()

    private struct Entry {
        let identifier: String
        let operation: RuntimeUserOperation
        var task: BGContinuedProcessingTask?
        var progressObserver: Task<Void, Never>?
    }
    private var entries: [UUID: Entry] = [:]

    func begin(_ operation: RuntimeUserOperation) {
        let environment = ProcessInfo.processInfo.environment
        guard UIApplication.shared.applicationState == .active,
              environment["HANLIN_UNIT_TEST_HOST"] != "1",
              environment["XCTestConfigurationFilePath"] == nil,
              entries[operation.id] == nil,
              !operation.snapshot.finished,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        // Some original entry points reuse their chat/session run identifier.
        // Scheduler registrations require a fresh identifier for every request.
        let identifier = bundleID + ".runtime." + UUID().uuidString.lowercased()
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self, weak operation] task in
            // The scheduler explicitly delivers this callback on the main queue.
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                guard let self, let operation else { task.setTaskCompleted(success: false); return }
                self.launched(task, operation: operation)
            }
        }
        guard registered else { return }
        entries[operation.id] = Entry(identifier: identifier, operation: operation)
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: String(localized: "Working on your request", table: "RuntimeLocalizable"),
            subtitle: String(localized: "Progress is saved as work continues", table: "RuntimeLocalizable")
        )
        request.strategy = .fail // Foreground work is already underway; never queue a replay.
        do { try BGTaskScheduler.shared.submit(request) }
        catch { entries.removeValue(forKey: operation.id) }
    }

    func end(_ operation: RuntimeUserOperation) {
        operation.finish()
        guard let entry = entries[operation.id], entry.operation === operation else { return }
        entries.removeValue(forKey: operation.id)
        entry.progressObserver?.cancel()
        if let task = entry.task {
            task.expirationHandler = nil
            task.setTaskCompleted(success: operation.snapshot.succeeded && operation.snapshot.reason == nil)
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: entry.identifier)
        }
    }

    private func launched(_ task: BGContinuedProcessingTask, operation: RuntimeUserOperation) {
        guard var entry = entries[operation.id], entry.operation === operation, !operation.snapshot.finished else {
            task.setTaskCompleted(success: operation.snapshot.succeeded && operation.snapshot.reason == nil)
            return
        }
        let reason = String(localized: "Background continuation ended by the system or its Cancel control.", table: "RuntimeLocalizable")
        task.expirationHandler = { [weak self, weak operation] in
            // Apple uses the same callback for resource expiry and native UI
            // cancellation. Preserve that ambiguity instead of inventing a cause.
            operation?.interrupt(reason: reason)
            Task { @MainActor in
                guard let self, let operation, let entry = self.entries[operation.id],
                      entry.operation === operation else { return }
                self.entries.removeValue(forKey: operation.id)
                entry.progressObserver?.cancel()
                entry.task?.expirationHandler = nil
                entry.task?.setTaskCompleted(success: false)
            }
        }
        // The model/tool workload has no known total. Only count actual stream
        // and journal bytes; never display an invented percent or heartbeat.
        task.progress.totalUnitCount = -1
        task.progress.completedUnitCount = operation.snapshot.outputBytes
        entry.task = task
        entry.progressObserver = Task { @MainActor [weak operation, weak task] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let operation, let task, !operation.snapshot.finished else { return }
                task.progress.completedUnitCount = operation.snapshot.outputBytes
            }
        }
        entries[operation.id] = entry
    }
}
