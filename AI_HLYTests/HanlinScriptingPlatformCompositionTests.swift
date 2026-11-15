import Foundation
import HanlinScriptingApplicationRuntime
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Scripting Platform application services", .serialized)
struct HanlinScriptingPlatformCompositionTests {
    @Test func unconfiguredAssistantIsExplicitlyUnavailable() async throws {
        let (root, platform) = makePlatform()
        defer { try? FileManager.default.removeItem(at: root) }
        await platform.publishCompactAgentConfig()
        try await expectUnavailable(platform)
    }

    @Test func requestChunksAndStreamFailureAreForwardedUnchanged() async throws {
        let (root, platform) = makePlatform()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = RecordingServices()
        services.streamFailure = .stream
        platform.configure(applicationServices: services)
        let request = HanlinScriptingAssistantRequest(
            kind: .streaming, prompt: "unchanged prompt", images: ["fixture-image"],
            schemaJSON: Data("{}".utf8), systemPrompt: "unchanged system",
            messagesJSON: Data("[]".utf8), provider: .custom("fixture-provider"), modelID: "fixture-model"
        )
        let stream = try await platform.performAssistant(request)
        var values: [String] = []
        do {
            for try await chunk in stream {
                switch chunk {
                case let .text(text): values.append("text:" + text)
                case let .reasoning(text): values.append("reasoning:" + text)
                default: Issue.record("Unexpected unit fixture chunk")
                }
            }
            Issue.record("Expected the original stream failure")
        } catch FixtureFailure.stream {}
        #expect(values == ["text:unit-text", "reasoning:unit-reasoning"])
        let forwarded = try #require(services.requests.first)
        #expect(services.requests.count == 1)
        #expect(forwarded.kind == request.kind)
        #expect(forwarded.prompt == request.prompt)
        #expect(forwarded.images == request.images)
        #expect(forwarded.schemaJSON == request.schemaJSON)
        #expect(forwarded.systemPrompt == request.systemPrompt)
        #expect(forwarded.messagesJSON == request.messagesJSON)
        #expect(forwarded.provider == request.provider)
        #expect(forwarded.modelID == request.modelID)
    }

    @Test func loaderFailureIsNotTranslated() async throws {
        let (root, platform) = makePlatform()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = RecordingServices()
        services.loadFailure = .loading
        platform.configure(applicationServices: services)
        do {
            _ = try await platform.performAssistant(.init(kind: .streaming))
            Issue.record("Expected the original loader failure")
        } catch FixtureFailure.loading {}
        #expect(services.requests.count == 1)
    }

    @Test func removingServicesDoesNotPublishOrClearTheirConfiguration() async throws {
        let (root, platform) = makePlatform()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = RecordingServices()
        platform.configure(applicationServices: services)
        await platform.publishCompactAgentConfig()
        let publicationCount = services.publicationCount
        #expect(publicationCount >= 1)
        platform.configure(applicationServices: nil)
        await platform.publishCompactAgentConfig()
        await Task.yield()
        #expect(services.publicationCount == publicationCount)
        try await expectUnavailable(platform)
        #expect(services.requests.isEmpty)
    }

    @Test func publicationFailureDoesNotDiscardTheAssistantService() async throws {
        let (root, platform) = makePlatform()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = RecordingServices()
        services.publicationFailure = .publishing
        platform.configure(applicationServices: services)
        await platform.publishCompactAgentConfig()
        let stream = try await platform.performAssistant(.init(kind: .streaming))
        var count = 0
        for try await _ in stream { count += 1 }
        #expect(count == 2)
        #expect(services.requests.count == 1)
    }

    @Test func platformInstancesDoNotShareApplicationServices() async throws {
        let (firstRoot, first) = makePlatform()
        let (secondRoot, second) = makePlatform()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let services = RecordingServices()
        first.configure(applicationServices: services)
        await second.publishCompactAgentConfig()
        try await expectUnavailable(second)
        _ = try await first.performAssistant(.init(kind: .streaming))
        #expect(services.requests.count == 1)
    }

    private func makePlatform() -> (URL, HanlinScriptingPlatform) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "platform-composition-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        return (root, HanlinScriptingPlatform(rootOverride: root))
    }

    private func expectUnavailable(_ platform: HanlinScriptingPlatform) async throws {
        do {
            _ = try await platform.performAssistant(.init(kind: .streaming))
            Issue.record("Unconfigured services must not fabricate an Assistant response")
        } catch let error as HanlinScriptingNativeError {
            #expect(error.code == "assistant_configuration_unavailable")
            #expect(error.name == "Error")
            #expect(error.message == "The Assistant configuration is unavailable.")
        }
    }

    private enum FixtureFailure: Error, Sendable {
        case loading, publishing, stream
    }

    @MainActor
    private final class RecordingServices: HanlinScriptingApplicationServices {
        var requests: [HanlinScriptingAssistantRequest] = []
        var publicationCount = 0
        var loadFailure: FixtureFailure?
        var publicationFailure: FixtureFailure?
        var streamFailure: FixtureFailure?

        func publishCompactAgentConfig() async throws {
            publicationCount += 1
            if let publicationFailure { throw publicationFailure }
        }

        func loadAssistant(_ request: HanlinScriptingAssistantRequest) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
            requests.append(request)
            if let loadFailure { throw loadFailure }
            let failure = streamFailure
            return AsyncThrowingStream { continuation in
                continuation.yield(.text("unit-text"))
                continuation.yield(.reasoning("unit-reasoning"))
                if let failure { continuation.finish(throwing: failure) }
                else { continuation.finish() }
            }
        }
    }
}
