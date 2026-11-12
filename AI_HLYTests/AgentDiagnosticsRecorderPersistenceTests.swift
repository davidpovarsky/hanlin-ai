import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Actual app diagnostic recorder persistence", .serialized)
struct AgentDiagnosticsRecorderPersistenceTests {
    @Test func actualRecorderReopensItsSessionAndDeviceKeyCapture() async throws {
        let defaults = UserDefaults.standard
        let oldLevel = defaults.object(forKey: AgentDiagnosticsConfiguration.levelKey)
        defer {
            if let oldLevel { defaults.set(oldLevel, forKey: AgentDiagnosticsConfiguration.levelKey) }
            else { defaults.removeObject(forKey: AgentDiagnosticsConfiguration.levelKey) }
        }
        defaults.set(AgentDiagnosticsLevel.fullLocalDebug.rawValue, forKey: AgentDiagnosticsConfiguration.levelKey)
        let runID = UUID()
        let recorder = try #require(await AgentDiagnosticsRecorder.start(runID: runID, groupID: UUID(), providerID: "test", modelID: "recorder-test"))
        let files = await recorder.fileURLs()
        defer { AgentDiagnosticsRecorder.deleteSessionFiles(jsonURL: files.json) }
        var request = URLRequest(url: URL(string: "https://capture-proof.invalid/v1/chat/completions")!)
        request.setValue("Bearer PRIVATE_RECORDER_TEST_ONLY", forHTTPHeaderField: "Authorization")
        let body = Data(#"{"model":"recorder-test","stream":true,"messages":[{"role":"user","content":"Capture test שלום🙂"}]}"#.utf8)
        request.httpBody = body
        let round = await recorder.beginRound(index: 1, trigger: "initialUserRequest", requestData: body)
        await recorder.recordModelRequest(roundID: round, requestData: body, httpHeaders: request.allHTTPHeaderFields)
        let attempt = UUID()
        recorder.journal.transportObserver(.request(id: attempt, request: request))
        recorder.journal.transportObserver(.bytes(id: attempt, data: Data("data: {\"choices\":[{\"delta\":{\"content\":\"ACTUAL_RECORDER_CAPTURE_שלום🙂\"}}]}\n\ndata: [DONE]\n\n".utf8)))
        recorder.journal.transportObserver(.end(id: attempt, error: nil))
        await recorder.complete(status: "completed")
        let session = try AgentDiagnosticsSession.decodeStoredFile(Data(contentsOf: files.json))
        #expect(session.runID == runID && session.isComplete && session.level == .fullLocalDebug)
        let review = try await AgentDiagnosticsRawReviewer.reviewLocally(sessionJSON: files.json, runID: runID, modelID: "recorder-test", apiType: "OpenAI")
        #expect(review.text.contains("ACTUAL_RECORDER_CAPTURE_שלום🙂"))
        #expect(!review.text.contains("PRIVATE_RECORDER_TEST_ONLY"))
        #expect(!review.text.contains("NOT_CAPTURED: no transport request or response records are available."))
    }
}
