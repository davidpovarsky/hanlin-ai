import HanlinLocalization
import BackgroundTasks
import Foundation
import OSLog
import UIKit

/// OS continuation for the original, foreground, user-started operation. The
/// scheduler attaches a lifetime to that producer; it never starts/replays work.
@MainActor
final class RuntimeBackgroundContinuation {
    static let shared = RuntimeBackgroundContinuation()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Hanlin", category: "BackgroundContinuation")

    private struct Entry {
        let identifier: String
        let operation: RuntimeUserOperation
        var task: BGContinuedProcessingTask?
        var handoffID: UIBackgroundTaskIdentifier = .invalid
        var progressObserver: Task<Void, Never>?
    }
    private var entries: [UUID: Entry] = [:]
    var onProtectionEnded: (@MainActor () -> Void)?

    /// MCP lifecycle must not kill the workers of a continued user operation.
    var isKeepingUserWorkAlive: Bool {
        entries.values.contains { entry in
            let snapshot = entry.operation.snapshot
            return !snapshot.finished && snapshot.reason == nil
                && (entry.task != nil || entry.handoffID != .invalid)
        }
    }

    func begin(_ operation: RuntimeUserOperation) {
        let environment = ProcessInfo.processInfo.environment
        guard UIApplication.shared.applicationState == .active,
              environment["HANLIN_UNIT_TEST_HOST"] != "1",
              environment["XCTestConfigurationFilePath"] == nil,
              entries[operation.id] == nil,
              !operation.snapshot.finished,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let identifier = bundleID + ".runtime." + UUID().uuidString.lowercased()
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self, weak operation] task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                guard let self, let operation else { task.setTaskCompleted(success: false); return }
                self.launched(task, operation: operation)
            }
        }
        guard registered else {
            logger.error("Registration rejected for operation \(operation.id.uuidString, privacy: .public)")
            return
        }
        entries[operation.id] = Entry(identifier: identifier, operation: operation)
        // Protect the original producer if the user leaves during asynchronous
        // scheduler admission. This bounded UIKit lease is not a replacement for
        // continued processing and is released as soon as admission launches.
        let handoffID = UIApplication.shared.beginBackgroundTask(withName: "Hanlin conversation admission") { [weak self, weak operation] in
            guard let self, let operation else { return }
            self.handoffExpired(operation)
        }
        entries[operation.id]?.handoffID = handoffID
        logger.info("Requested continuation for \(operation.id.uuidString, privacy: .public)")
        let title = "Hanlin"
        let subtitle = subtitle(for: operation.snapshot.presentation)
        // iOS 27 submission is asynchronous and belongs off the main thread.
        Task.detached(priority: .userInitiated) { [weak self, weak operation] in
            guard let operation, !operation.snapshot.finished else { return }
            let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
            // Queue admission for THIS existing operation when resources are
            // busy. launched() verifies its identity/lifetime and only attaches;
            // no closure here dispatches or replays the user's model/tool work.
            request.strategy = .queue
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
                await self?.submissionFinished(operation, identifier: identifier, failure: nil)
            } catch {
                let error = error as NSError
                await self?.submissionFinished(operation, identifier: identifier,
                    failure: "\(error.domain):\(error.code)")
            }
        }
    }

    private func submissionFinished(_ operation: RuntimeUserOperation, identifier: String, failure: String?) {
        guard let entry = entries[operation.id], entry.operation === operation, entry.identifier == identifier else {
            if failure == nil { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
            return
        }
        if operation.snapshot.finished {
            end(operation)
        } else if let failure, entry.task == nil {
            logger.error("Admission failed for \(operation.id.uuidString, privacy: .public): \(failure, privacy: .public)")
            // Foreground work and the bounded handoff remain valid. If there is
            // no handoff lease, do not pretend there is background protection.
            if entry.handoffID == .invalid {
                entries.removeValue(forKey: operation.id)
                releaseBackgroundResourcesIfIdle()
            }
        }
    }

    func end(_ operation: RuntimeUserOperation) {
        operation.finish()
        guard let entry = entries[operation.id], entry.operation === operation else { return }
        entries.removeValue(forKey: operation.id)
        entry.progressObserver?.cancel()
        let snapshot = operation.snapshot
        if let task = entry.task {
            task.expirationHandler = nil
            publishProgress(snapshot, to: task)
            task.setTaskCompleted(success: snapshot.succeeded && snapshot.reason == nil)
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: entry.identifier)
        }
        if entry.handoffID != .invalid { UIApplication.shared.endBackgroundTask(entry.handoffID) }
        logger.info("Finished continuation \(operation.id.uuidString, privacy: .public); success=\(snapshot.succeeded && snapshot.reason == nil, privacy: .public); units=\(snapshot.completedWorkUnits, privacy: .public); bytes=\(snapshot.outputBytes, privacy: .public)")
        releaseBackgroundResourcesIfIdle()
    }

    private func handoffExpired(_ operation: RuntimeUserOperation) {
        guard var entry = entries[operation.id], entry.operation === operation else { return }
        if entry.handoffID != .invalid { UIApplication.shared.endBackgroundTask(entry.handoffID) }
        entry.handoffID = .invalid
        entries[operation.id] = entry
        guard entry.task == nil else { return }
        logger.error("Admission handoff expired for \(operation.id.uuidString, privacy: .public)")
        if UIApplication.shared.applicationState != .active {
            operation.interrupt(reason: String(localized: "Background continuation was not available before the system suspended the app.", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle))
            end(operation)
        }
    }

    private func launched(_ task: BGContinuedProcessingTask, operation: RuntimeUserOperation) {
        guard var entry = entries[operation.id], entry.operation === operation,
              entry.identifier == task.identifier, !operation.snapshot.finished,
              operation.snapshot.reason == nil else {
            task.setTaskCompleted(success: false)
            return
        }
        let reason = String(localized: "Background continuation ended by the system or its Cancel control.", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        task.expirationHandler = { [weak self, weak operation] in
            // Apple uses this callback for resource expiry and native Cancel.
            // Retain that ambiguity; cancellation must never restart writes.
            operation?.interrupt(reason: reason)
            Task { @MainActor in
                guard let self, let operation else { return }
                self.logger.error("System expiry/Cancel for \(operation.id.uuidString, privacy: .public)")
                self.end(operation)
            }
        }
        let initialSnapshot = operation.snapshot
        publishProgress(initialSnapshot, to: task)
        if entry.handoffID != .invalid { UIApplication.shared.endBackgroundTask(entry.handoffID) }
        entry.handoffID = .invalid
        entry.task = task
        entry.progressObserver = Task { @MainActor [weak self, weak operation, weak task] in
            // Compare against the state actually published above. The producer
            // can advance before this scheduled observer first starts running.
            var lastUnits = initialSnapshot.completedWorkUnits
            var lastPresentation = initialSnapshot.presentation
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, let operation, let task else { return }
                let snapshot = operation.snapshot
                guard !snapshot.finished else { return }
                let presentationChanged = snapshot.presentation != lastPresentation
                guard snapshot.completedWorkUnits != lastUnits || presentationChanged else { continue }
                lastUnits = snapshot.completedWorkUnits
                lastPresentation = snapshot.presentation
                self.publishProgress(snapshot, to: task, updatePresentation: presentationChanged)
            }
        }
        entries[operation.id] = entry
        logger.info("Continuation launched for \(operation.id.uuidString, privacy: .public)")
    }

    private func publishProgress(_ snapshot: RuntimeUserOperation.Snapshot, to task: BGContinuedProcessingTask,
                                 updatePresentation: Bool = true) {
        // A negative total fixes fractionCompleted at zero even while bytes
        // arrive. Track actual discovered/processed units and finalization;
        // reading this snapshot or passing time never advances progress.
        task.progress.totalUnitCount = snapshot.progressTotalUnits
        task.progress.completedUnitCount = snapshot.progressCompletedUnits
        if updatePresentation {
            task.updateTitle("Hanlin", subtitle: subtitle(for: snapshot.presentation))
        }
    }

    private func subtitle(for presentation: RuntimeUserOperation.Presentation) -> String {
        switch presentation {
        case .waitingForResponse:
            String(localized: "Waiting for a response", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        case .thinking:
            String(localized: "Thinking", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        case .responding:
            String(localized: "Writing the response", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        case .awaitingApproval:
            String(localized: "Waiting for your approval", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        case .tool(let title):
            title
        case .completed:
            String(localized: "Response complete", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        case .stopped:
            String(localized: "Response stopped", table: "RuntimeLocalizable", bundle: HanlinLocalization.bundle)
        }
    }

    private func releaseBackgroundResourcesIfIdle() {
        guard !isKeepingUserWorkAlive, UIApplication.shared.applicationState == .background else { return }
        onProtectionEnded?()
    }
}
