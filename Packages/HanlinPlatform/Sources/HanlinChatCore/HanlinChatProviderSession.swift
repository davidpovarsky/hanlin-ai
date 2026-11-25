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
