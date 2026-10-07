import Testing
import Foundation
@testable import AI_Hanlin

@Suite("Apple Local Model Providers Contract Tests")
struct AppleLocalProvidersTests {

    @Test("AppleFoundationModelCapability reports typed state without crashing")
    func testCapabilityDetection() {
        let capability = AppleFoundationModelCapability.current()
        #expect(!capability.modelIdentifier.isEmpty)
        if !capability.isAvailable {
            #expect(capability.unavailabilityReason != nil)
        }
    }

    @Test("AppleFoundationModelsProvider throws typed unavailable on non-compatible host")
    func testFoundationModelProviderUnavailable() async {
        let provider = await AppleFoundationModelsProvider.shared
        let available = await provider.isAvailable()
        if !available {
            do {
                try await provider.generate(prompt: "Hello") { _ in true }
                Issue.record("Expected unavailable error")
            } catch let error as AppleFoundationModelError {
                switch error {
                case .unavailable(let reason):
                    #expect(!reason.isEmpty)
                default:
                    Issue.record("Unexpected error: \(error)")
                }
            } catch {
                Issue.record("Unexpected non-Apple error: \(error)")
            }
        }
    }

    @Test("CoreAI provider rejects non-existent model file")
    func testCoreAINonExistentFile() async {
        let provider = await CoreAILanguageModelProvider.shared
        let bogusURL = URL(fileURLWithPath: "/nonexistent/test.aimodel")
        do {
            _ = try await provider.loadAndSpecialize(modelURL: bogusURL)
            Issue.record("Expected modelNotFound error")
        } catch let error as CoreAIModelError {
            switch error {
            case .modelNotFound:
                #expect(true)
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("CoreAI provider rejects invalid file format")
    func testCoreAIInvalidFormat() async throws {
        let provider = await CoreAILanguageModelProvider.shared
        let tempDir = FileManager.default.temporaryDirectory
        let wrongFile = tempDir.appending(path: "test_\(UUID().uuidString).txt")
        try "dummy".write(to: wrongFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: wrongFile) }

        do {
            _ = try await provider.loadAndSpecialize(modelURL: wrongFile)
            Issue.record("Expected unsupportedModelFormat error")
        } catch let error as CoreAIModelError {
            switch error {
            case .unsupportedModelFormat(let ext):
                #expect(ext == "txt")
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
