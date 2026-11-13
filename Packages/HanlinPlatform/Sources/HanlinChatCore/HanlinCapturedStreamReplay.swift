import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HanlinCapturedStreamChunk: Codable, Sendable, Equatable {
    public let bytes: Data
    public let offsetNanoseconds: UInt64

    public init(bytes: Data, offsetNanoseconds: UInt64 = 0) {
        self.bytes = bytes
        self.offsetNanoseconds = offsetNanoseconds
    }
}

public struct HanlinCapturedStreamReplayResult: Sendable {
    public let directContent: String
    public let directReasoning: String
    public let sdkContent: String
    public let sdkReasoning: String
    public let sdkEvents: [HanlinAISDKStreamEvent]
    public let directFinishReason: String?
    public let sdkFinishReason: String?
    public let sdkError: String?
    public let warnings: [String]
    public let firstContentMismatchByteOffset: Int?
    public let fetchCount: Int
}

/// Response-only offline replay through the actual direct parser and SDK agent
/// adapter. This type has no URLSession, tool definitions, credential lookup,
/// persistence, or network fallback. It does not certify APIManager/UI parity.
public enum HanlinCapturedStreamReplay {
    public static func replay(
        chunks: [HanlinCapturedStreamChunk],
        configuration: HanlinChatModelConfiguration,
        statusCode: Int = 200,
        responseHeaders: [String: String] = ["Content-Type": "text/event-stream"],
        playbackSpeed: Double? = nil
    ) async throws -> HanlinCapturedStreamReplayResult {
        guard (100...599).contains(statusCode),
              chunks.reduce(0, { $0 + $1.bytes.count }) <= 64 * 1024 * 1024,
              playbackSpeed.map({ $0.isFinite && $0 > 0 }) ?? true else { throw URLError(.cannotDecodeContentData) }
        var lastOffset: UInt64 = 0
        for chunk in chunks {
            guard chunk.offsetNanoseconds >= lastOffset else { throw URLError(.cannotDecodeContentData) }
            lastOffset = chunk.offsetNanoseconds
        }
        let parser = HanlinChatStreamParser(apiType: configuration.apiType)
        var pending = Data(), directContent = "", directReasoning = ""
        var directFinish: String?, directDone = false, warnings: [String] = []
        func parse(_ line: Data, partial: Bool) {
            if directDone { return }
            guard let text = String(data: line, encoding: .utf8) else {
                warnings.append("Invalid source UTF-8; direct parser line was not repaired.")
                return
            }
            if partial { warnings.append("Source ends in an unterminated SSE line.") }
            if text.contains("\u{FFFD}") { warnings.append("Source already contains U+FFFD; presence alone does not identify corruption.") }
            guard let event = parser.parse(line: text) else { return }
            directContent += event.content ?? ""
            directReasoning += event.reasoning ?? ""
            directFinish = event.finishReason ?? directFinish
            directDone = directDone || event.isDone
        }
        for chunk in chunks {
            try Task.checkCancellation()
            pending.append(chunk.bytes)
            while let newline = pending.firstIndex(of: 0x0A) {
                parse(Data(pending[...newline]), partial: false)
                pending.removeSubrange(...newline)
            }
        }
        if !pending.isEmpty { parse(pending, partial: true) }
        if !directDone { warnings.append("Source has no observed completion boundary.") }

        let source = ReplaySource(chunks: chunks, statusCode: statusCode, headers: responseHeaders, speed: playbackSpeed)
        let fetch: FetchFunction = { request in try await source.response(for: request) }
        let engine = try HanlinAISDKAgentEngine(configuration: configuration, fetch: fetch)
        var events: [HanlinAISDKStreamEvent] = [], sdkContent = "", sdkReasoning = ""
        var sdkFinish: String?, sdkError: String?
        do {
            let stream = try await engine.stream(
                messages: [.init(role: .user, text: "Offline captured response replay")],
                baseSystemPrompt: nil, tools: [], maxSteps: 1,
                prepareStep: { HanlinAISDKStepPreparation(activeToolAliases: [], loadedSkillIDs: []) })
            for try await event in stream {
                try Task.checkCancellation()
                events.append(event)
                switch event {
                case .textDelta(let text): sdkContent += text
                case .reasoningDelta(let text): sdkReasoning += text
                case .finished(let reason, _): sdkFinish = reason
                default: break
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            sdkError = String(describing: error)
        }
        let count = await source.fetchCount
        if count > 1 { warnings.append("SDK requested another attempt; no recorded response was replayed twice and no network fallback exists.") }
        return HanlinCapturedStreamReplayResult(
            directContent: directContent, directReasoning: directReasoning,
            sdkContent: sdkContent, sdkReasoning: sdkReasoning, sdkEvents: events,
            directFinishReason: directFinish, sdkFinishReason: sdkFinish, sdkError: sdkError,
            warnings: warnings, firstContentMismatchByteOffset: firstMismatch(directContent, sdkContent), fetchCount: count)
    }

    private static func firstMismatch(_ left: String, _ right: String) -> Int? {
        let a = Array(left.utf8), b = Array(right.utf8)
        for index in 0..<min(a.count, b.count) where a[index] != b[index] { return index }
        return a.count == b.count ? nil : min(a.count, b.count)
    }

    private actor ReplaySource {
        let chunks: [HanlinCapturedStreamChunk]
        let statusCode: Int
        let headers: [String: String]
        let speed: Double?
        private(set) var fetchCount = 0

        init(chunks: [HanlinCapturedStreamChunk], statusCode: Int, headers: [String: String], speed: Double?) {
            self.chunks = chunks; self.statusCode = statusCode; self.headers = headers; self.speed = speed
        }

        func response(for request: URLRequest) throws -> FetchResponse {
            fetchCount += 1
            guard fetchCount == 1, let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers) else {
                throw URLError(.resourceUnavailable)
            }
            let chunks = self.chunks, speed = self.speed
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    do {
                        var previous: UInt64 = 0
                        for chunk in chunks {
                            try Task.checkCancellation()
                            if let speed {
                                let interval = Double(chunk.offsetNanoseconds - previous) / speed
                                guard interval < Double(UInt64.max) else { throw URLError(.cannotDecodeContentData) }
                                try await Task.sleep(nanoseconds: UInt64(interval))
                            }
                            previous = chunk.offsetNanoseconds
                            continuation.yield(chunk.bytes)
                        }
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return FetchResponse(body: .stream(stream), urlResponse: response)
        }
    }
}
