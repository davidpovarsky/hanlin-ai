import Testing
import Foundation
@testable import AI_Hanlin

private final class MockFoundationBackend: AppleFoundationModelSessionBackend, @unchecked Sendable {
    let chunks: [String]
    let delayNanoseconds: UInt64

    init(chunks: [String] = ["Hello", " world", "!"], delayNanoseconds: UInt64 = 0) {
        self.chunks = chunks
        self.delayNanoseconds = delayNanoseconds
    }

    func generate(
        prompt: String,
        images: [Data],
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws {
        for chunk in chunks {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            try Task.checkCancellation()
            let shouldContinue = onDelta(chunk)
            if !shouldContinue { break }
        }
    }
}

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
        AppleFoundationModelCapability.overrideCapability = AppleFoundationModelCapability(
            isAvailable: false,
            supportsMultimodal: false,
            modelIdentifier: "apple.system.language-model",
            unavailabilityReason: "Test simulated unavailable state"
        )
        defer { AppleFoundationModelCapability.overrideCapability = nil }

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

    @Test("AppleFoundationModelsProvider rejects images when model does not support multimodal")
    func testFoundationModelProviderRejectsImagesWhenNonMultimodal() async {
        let provider = await AppleFoundationModelsProvider.shared
        AppleFoundationModelCapability.overrideCapability = AppleFoundationModelCapability(
            isAvailable: true,
            supportsMultimodal: false,
            modelIdentifier: "apple.system.language-model",
            unavailabilityReason: nil
        )
        defer { AppleFoundationModelCapability.overrideCapability = nil }

        let dummyImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        do {
            try await provider.generate(prompt: "Describe this", images: [dummyImageData]) { _ in true }
            Issue.record("Expected unsupportedModality error")
        } catch let error as AppleFoundationModelError {
            switch error {
            case .unsupportedModality(let message):
                #expect(!message.isEmpty)
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AppleFoundationModelsProvider streams tokens in order via injected backend")
    func testFoundationModelProviderStreamingViaBackend() async throws {
        let provider = await AppleFoundationModelsProvider.shared
        AppleFoundationModelCapability.overrideCapability = AppleFoundationModelCapability(
            isAvailable: true,
            supportsMultimodal: false,
            modelIdentifier: "apple.system.language-model",
            unavailabilityReason: nil
        )
        let mockBackend = MockFoundationBackend(chunks: ["Swift", " ", "Apple", " ", "Intelligence"])
        await MainActor.run {
            provider.backend = mockBackend
        }
        defer {
            AppleFoundationModelCapability.overrideCapability = nil
            Task { @MainActor in provider.backend = nil }
        }

        final class Accumulator: @unchecked Sendable {
            var items: [String] = []
            func append(_ item: String) { items.append(item) }
        }
        let acc = Accumulator()
        try await provider.generate(prompt: "Tell me about Swift") { delta in
            acc.append(delta)
            return true
        }

        #expect(acc.items == ["Swift", " ", "Apple", " ", "Intelligence"])
        #expect(acc.items.joined() == "Swift Apple Intelligence")
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

    @Test("CoreAI provider rejects empty model file container")
    func testCoreAIEmptyModelFileRejected() async throws {
        let provider = await CoreAILanguageModelProvider.shared
        let tempDir = FileManager.default.temporaryDirectory
        let emptyModel = tempDir.appending(path: "empty_\(UUID().uuidString).aimodel")
        try Data().write(to: emptyModel)
        defer { try? FileManager.default.removeItem(at: emptyModel) }

        do {
            _ = try await provider.loadAndSpecialize(modelURL: emptyModel)
            Issue.record("Expected specializationFailed error for empty asset")
        } catch let error as CoreAIModelError {
            switch error {
            case .specializationFailed:
                #expect(true)
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("CoreAI provider requires official dependency and reports blockedDependency on valid container")
    func testCoreAIGenerateThrowsBlockedDependency() async throws {
        let provider = await CoreAILanguageModelProvider.shared
        let tempDir = FileManager.default.temporaryDirectory
        let validModel = tempDir.appending(path: "valid_\(UUID().uuidString).aimodel")
        try Data("mock-coreai-weights".utf8).write(to: validModel)
        defer { try? FileManager.default.removeItem(at: validModel) }

        do {
            _ = try await provider.loadAndSpecialize(modelURL: validModel)
            Issue.record("Expected blockedDependency error on host")
        } catch let error as CoreAIModelError {
            switch error {
            case .blockedDependency:
                #expect(true)
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
