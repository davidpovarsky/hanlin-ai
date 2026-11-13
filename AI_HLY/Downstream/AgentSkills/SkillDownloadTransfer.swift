import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SkillDownloadProgress: Sendable {
    let receivedBytes: Int64
    let expectedBytes: Int64?
}

/// The optional caller budget bounds the file, never an in-memory accumulator.
/// Each request owns a separate delegate so late callbacks cannot finish a
/// subsequent download made through the same downloader.
final class BoundedStreamDownloader: @unchecked Sendable {
    let maxBytes: Int64?
    private let configuration: URLSessionConfiguration
    private let progress: (@Sendable (SkillDownloadProgress) -> Void)?

    init(maxBytes: Int64? = nil, sessionConfiguration: URLSessionConfiguration = .ephemeral,
         progress: (@Sendable (SkillDownloadProgress) -> Void)? = nil) {
        self.maxBytes = maxBytes
        configuration = sessionConfiguration
        self.progress = progress
    }

    func download(from url: URL) async throws -> (URL, HTTPURLResponse) {
        try await download(request: URLRequest(url: url))
    }

    func download(request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        guard request.url?.scheme?.lowercased() == "https" else { throw SkillImportError.nonHTTPSURLForbidden }
        try Task.checkCancellation()
        let transfer = try SkillFileDownloadTransfer(maxBytes: maxBytes, configuration: configuration, progress: progress)
        return try await transfer.run(request)
    }
}

private final class SkillFileDownloadTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL
    private let maxBytes: Int64?
    private let configuration: URLSessionConfiguration
    private let progress: (@Sendable (SkillDownloadProgress) -> Void)?
    private var file: FileHandle?
    private var receivedBytes: Int64 = 0
    private var lastProgressTime = Date.distantPast
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var finished = false

    init(maxBytes: Int64?, configuration: URLSessionConfiguration,
         progress: (@Sendable (SkillDownloadProgress) -> Void)?) throws {
        if let maxBytes, maxBytes < 0 { throw SkillImportError.downloadFailed("Download budget must not be negative.") }
        self.maxBytes = maxBytes
        self.configuration = configuration
        self.progress = progress
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("skill-download-\(UUID().uuidString).part")
        super.init()
        try Data().write(to: fileURL, options: .withoutOverwriting)
        do { file = try FileHandle(forWritingTo: fileURL) }
        catch { try? FileManager.default.removeItem(at: fileURL); throw error }
    }

    deinit {
        try? file?.close()
        if !finished { try? FileManager.default.removeItem(at: fileURL) }
    }

    func run(_ request: URLRequest) async throws -> (URL, HTTPURLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if finished {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: request)
                lock.unlock()
                task.resume()
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            finish(.failure(SkillImportError.nonHTTPSURLForbidden))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(SkillImportError.downloadFailed("Non-HTTP response")))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(.failure(SkillImportError.downloadFailed("HTTP Status \(http.statusCode)")))
            return
        }
        if let maxBytes, http.expectedContentLength > maxBytes {
            completionHandler(.cancel)
            finish(.failure(SkillImportError.downloadExceedsLimit(http.expectedContentLength)))
            return
        }
        lock.lock()
        let active = !finished
        if active { self.response = http }
        lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished, let file else { lock.unlock(); return }
        let (next, overflow) = receivedBytes.addingReportingOverflow(Int64(data.count))
        if overflow {
            lock.unlock()
            finish(.failure(SkillImportError.downloadFailed("Received byte count cannot be represented.")))
            return
        }
        if let maxBytes, next > maxBytes {
            lock.unlock()
            finish(.failure(SkillImportError.downloadExceedsLimit(next)))
            return
        }
        do { try file.write(contentsOf: data) }
        catch { lock.unlock(); finish(.failure(error)); return }
        receivedBytes = next
        let expected = response?.expectedContentLength
        let update = SkillDownloadProgress(receivedBytes: next, expectedBytes: expected.flatMap { $0 >= 0 ? $0 : nil })
        let now = Date()
        let report = now.timeIntervalSince(lastProgressTime) >= 0.1
        if report { lastProgressTime = now }
        lock.unlock()
        if report { progress?(update) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let response = self.response
        lock.unlock()
        if let response { finish(.success((fileURL, response))) }
        else { finish(.failure(SkillImportError.downloadFailed("Missing response"))) }
    }

    private func finish(_ result: Result<(URL, HTTPURLResponse), Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        var delivered = result
        do { try file?.close() }
        catch { delivered = .failure(error) }
        file = nil
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        self.session = nil
        let update = SkillDownloadProgress(receivedBytes: receivedBytes,
            expectedBytes: response.flatMap { $0.expectedContentLength >= 0 ? $0.expectedContentLength : nil })
        lock.unlock()
        // Never call an external continuation/session while holding the lock.
        // A failed/cancelled transfer owns only its unique staging file.
        switch delivered {
        case .success:
            session?.finishTasksAndInvalidate()
            progress?(update)
        case .failure:
            session?.invalidateAndCancel()
            try? FileManager.default.removeItem(at: fileURL)
        }
        continuation?.resume(with: delivered)
    }
}
