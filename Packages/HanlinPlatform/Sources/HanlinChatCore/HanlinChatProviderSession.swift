import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A provider endpoint is an admitted credential destination. HTTP redirects
/// must not create an additional request outside that admission boundary.
/// Keep the original 3xx response so the existing provider error path handles it.
final class HanlinChatProviderSession: @unchecked Sendable {
    let session: URLSession

    init(configuration: URLSessionConfiguration) {
        session = URLSession(
            configuration: configuration,
            delegate: NoRedirects(),
            delegateQueue: nil
        )
    }

    deinit { session.finishTasksAndInvalidate() }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}

/// Original SDK streams may stop producing events before their provider returns.
/// Bind native request cancellation to the owning Hanlin turn, independently of
/// the SDK's intentionally graceful stop() operation. Child Tasks inherit only
/// this turn's value; a shared fetch/session can serve other turns concurrently.
final class HanlinChatTransportCancellation: @unchecked Sendable {
    @TaskLocal static var current: HanlinChatTransportCancellation?

    private let lock = NSLock()
    private var cancelled = false
    private var callbacks: [UUID: @Sendable () -> Void] = [:]

    func checkCancellation() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }

    func register(_ callback: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let alreadyCancelled = lock.withLock {
            if cancelled { return true }
            callbacks[id] = callback
            return false
        }
        if alreadyCancelled { callback() }
        return id
    }

    func unregister(_ id: UUID?) {
        guard let id else { return }
        _ = lock.withLock { callbacks.removeValue(forKey: id) }
    }

    func cancel() {
        let pending = lock.withLock {
            cancelled = true
            let pending = Array(callbacks.values)
            callbacks.removeAll()
            return pending
        }
        for callback in pending { callback() }
    }
}
