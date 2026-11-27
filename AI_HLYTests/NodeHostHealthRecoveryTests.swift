import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Node host recovery observation")
struct NodeHostHealthRecoveryTests {
    @Test func idleCommandObservationClearsTheFailureWithoutRestartingTheApp() {
        var observation = NodeHostHealthObservation()
        var snapshot = failedSnapshot()
        #expect(snapshot.activeExecutionCount == 0)

        #expect(observation.receivedResponse(snapshot: &snapshot, diagnostic: "Authenticated idle observer recovered"))

        #expect(snapshot.state == .ready)
        #expect(snapshot.lastErrorCode == nil && snapshot.healthCategory == nil)
        #expect(snapshot.lastDiagnostic == "Authenticated idle observer recovered")
        #expect(snapshot.version == "24.5.0")
        #expect(snapshot.activeExecutionCount == 0)
    }

    @Test func jobObservationRecoversTheExistingExecutionsWithoutResettingTheirCount() {
        var observation = NodeHostHealthObservation()
        var snapshot = failedSnapshot()
        snapshot.activeExecutionCount = 3

        observation.receivedResponse(snapshot: &snapshot, diagnostic: "Same jobs observed")

        #expect(snapshot.state == .executing)
        #expect(snapshot.activeExecutionCount == 3)
        #expect(snapshot.lastErrorCode == nil && snapshot.healthCategory == nil)
    }

    @Test func lateHealthProbeFailureCannotSupersedeANewerSuccessfulObservation() {
        var observation = NodeHostHealthObservation()
        var snapshot = failedSnapshot()
        let pendingProbe = observation.generation
        #expect(!observation.supersedesProbe(startedAt: pendingProbe))

        observation.receivedResponse(snapshot: &snapshot, diagnostic: "Recovered while health request was pending")

        #expect(observation.supersedesProbe(startedAt: pendingProbe))
        #expect(snapshot.state == .ready)
        let laterProbe = observation.generation
        #expect(!observation.supersedesProbe(startedAt: laterProbe), "A new unanswered probe is not excused by an older success")
    }

    @Test func lateResponseCannotReviveAConfirmedProcessExit() {
        var observation = NodeHostHealthObservation()
        var snapshot = failedSnapshot()
        snapshot.state = .appRestartRequired
        snapshot.lastErrorCode = "node_process_exited"
        snapshot.lastDiagnostic = "Native thread returned"
        let generation = observation.generation

        #expect(!observation.receivedResponse(snapshot: &snapshot, diagnostic: "Late buffered response"))

        #expect(snapshot.state == .appRestartRequired)
        #expect(snapshot.lastErrorCode == "node_process_exited")
        #expect(snapshot.lastDiagnostic == "Native thread returned")
        #expect(observation.generation == generation)
    }

    private func failedSnapshot() -> RuntimeSnapshot {
        var snapshot = RuntimeSnapshot.stopped(.node)
        snapshot.state = .failed
        snapshot.version = "24.5.0"
        snapshot.lastErrorCode = "node_health_unreachable"
        snapshot.healthCategory = NodeHostHealthFailure.transient.rawValue
        snapshot.lastDiagnostic = "Reconnecting job observation"
        return snapshot
    }
}
