import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Skill import attempt-scoped presentation", .serialized)
struct SkillImportPresentationStateTests {
    @Test("Cancel then retry rejects queued progress, error and cancellation from the old request")
    func cancelledCallbacksCannotStopRetry() {
        let state = SkillImportPresentationState()
        let old = state.beginInspection()
        let queuedProgress = { state.recordProgress(attempt: old, received: 900, expected: 1_000) }
        let queuedFailure = { state.inspectionFailed(attempt: old, message: "old failure") }
        state.invalidate()
        let current = state.beginInspection()
        state.recordProgress(attempt: current, received: 20, expected: 100)
        queuedProgress()
        queuedFailure()
        state.inspectionCancelled(attempt: old)
        #expect(state.isProcessing)
        #expect(state.downloadedBytes == 20)
        #expect(state.expectedDownloadBytes == 100)
        #expect(state.errorMessage == nil)
    }

    @Test("An obsolete staged result cannot become the current preview")
    func oldPreviewCannotReplaceRetry() {
        let state = SkillImportPresentationState()
        let old = state.beginInspection()
        let current = state.beginInspection()
        #expect(!state.preparePreview(attempt: old))
        #expect(state.isProcessing)
        #expect(state.beginInstallation() == nil)
        #expect(state.preparePreview(attempt: current))
        #expect(!state.isProcessing)
        #expect(state.beginInstallation() == current)
    }

    @Test("Inspection callbacks of the same request cannot overwrite its later installation phase")
    func inspectionCallbacksCannotChangeInstallation() {
        let state = SkillImportPresentationState()
        let current = state.beginInspection()
        #expect(state.preparePreview(attempt: current))
        #expect(state.beginInstallation() == current)
        state.recordProgress(attempt: current, received: 900, expected: 1_000)
        state.inspectionFailed(attempt: current, message: "late inspection failure")
        state.inspectionCancelled(attempt: current)
        #expect(state.isInstalling(attempt: current))
        #expect(state.downloadedBytes == 0)
        #expect(state.errorMessage == nil)
    }

    @Test("A stale installation result cannot hide a newer request's error")
    func oldInstallationCannotClearCurrentFailure() {
        let state = SkillImportPresentationState()
        let old = state.beginInspection()
        #expect(state.preparePreview(attempt: old))
        #expect(state.beginInstallation() == old)
        state.invalidate()
        let current = state.beginInspection()
        state.inspectionFailed(attempt: current, message: "new failure")
        #expect(!state.finishInstallation(attempt: old, message: "old success"))
        state.installationFailed(attempt: old, message: "old failure")
        #expect(state.errorMessage == "new failure")
        #expect(state.successMessage == nil)
        #expect(!state.isProcessing)
        #expect(!state.isInstalling(attempt: old))
    }

    @Test("A current install failure remains retryable without authorizing a stale attempt")
    func currentInstallationFailureCanRetry() {
        let state = SkillImportPresentationState()
        let current = state.beginInspection()
        #expect(state.preparePreview(attempt: current))
        #expect(state.beginInstallation() == current)
        state.installationFailed(attempt: current, message: "install failure")
        #expect(!state.isProcessing)
        #expect(state.errorMessage == "install failure")
        #expect(state.beginInstallation() == current)
        #expect(state.errorMessage == nil)
        #expect(state.isInstalling(attempt: current))
    }

    @Test("A finished installation rejects later callbacks, and a new request clears old presentation data")
    func successIsNotOverwrittenByLateCallbacks() {
        let state = SkillImportPresentationState()
        let current = state.beginInspection()
        #expect(state.preparePreview(attempt: current))
        #expect(state.beginInstallation() == current)
        #expect(state.finishInstallation(attempt: current, message: "installed"))
        state.installationFailed(attempt: current, message: "late failure")
        state.inspectionFailed(attempt: current, message: "late inspection failure")
        #expect(state.successMessage == "installed")
        #expect(state.errorMessage == nil)
        #expect(!state.isProcessing)
        _ = state.beginInspection()
        #expect(state.successMessage == nil)
        #expect(state.isProcessing)
    }

    @Test("Dismissal invalidates all outstanding updates without retaining a false busy state")
    func invalidationRejectsQueuedCallbacks() {
        let state = SkillImportPresentationState()
        let current = state.beginInspection()
        state.recordProgress(attempt: current, received: 10, expected: 100)
        state.invalidate()
        state.recordProgress(attempt: current, received: 90, expected: 100)
        state.inspectionFailed(attempt: current, message: "late error")
        #expect(!state.preparePreview(attempt: current))
        #expect(state.beginInstallation() == nil)
        #expect(!state.isProcessing)
        #expect(state.downloadedBytes == 0)
        #expect(state.expectedDownloadBytes == nil)
        #expect(state.errorMessage == nil)
    }
}
