import Foundation
import Observation

/// Ephemeral import-screen state only. It neither inspects nor executes skills.
@MainActor
@Observable
final class SkillImportPresentationState {
    private enum Phase { case idle, inspecting, preview, installing, installed }
    private var phase: Phase = .idle
    private var activeAttempt: UUID?
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var downloadedBytes: Int64 = 0
    private(set) var expectedDownloadBytes: Int64?

    var isProcessing: Bool { phase == .inspecting || phase == .installing }

    func beginInspection() -> UUID {
        let attempt = UUID()
        activeAttempt = attempt
        phase = .inspecting
        errorMessage = nil
        successMessage = nil
        downloadedBytes = 0
        expectedDownloadBytes = nil
        return attempt
    }

    func invalidate() {
        activeAttempt = nil
        phase = .idle
        errorMessage = nil
        successMessage = nil
        downloadedBytes = 0
        expectedDownloadBytes = nil
    }

    func recordProgress(attempt: UUID, received: Int64, expected: Int64?) {
        guard activeAttempt == attempt, phase == .inspecting else { return }
        downloadedBytes = received
        expectedDownloadBytes = expected
    }

    func inspectionFailed(attempt: UUID, message: String) {
        guard activeAttempt == attempt, phase == .inspecting else { return }
        phase = .idle
        errorMessage = message
    }

    func inspectionCancelled(attempt: UUID) {
        guard activeAttempt == attempt, phase == .inspecting else { return }
        invalidate()
    }

    func preparePreview(attempt: UUID) -> Bool {
        guard activeAttempt == attempt, phase == .inspecting else { return false }
        phase = .preview
        return true
    }

    func beginInstallation() -> UUID? {
        guard let attempt = activeAttempt, phase == .preview else { return nil }
        phase = .installing
        errorMessage = nil
        return attempt
    }

    func isInstalling(attempt: UUID) -> Bool {
        activeAttempt == attempt && phase == .installing
    }

    func installationFailed(attempt: UUID, message: String) {
        guard activeAttempt == attempt, phase == .installing else { return }
        phase = .preview
        errorMessage = message
    }

    func installationCancelled(attempt: UUID) {
        guard activeAttempt == attempt, phase == .installing else { return }
        phase = .preview
    }

    func finishInstallation(attempt: UUID, message: String) -> Bool {
        guard activeAttempt == attempt, phase == .installing else { return false }
        phase = .installed
        successMessage = message
        return true
    }
}
