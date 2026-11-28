import Foundation
import SwiftUI
import Synchronization

struct HanlinScriptWidgetResources {
    let files: [String: URL]
    struct ImageResource { let path: URL }
    func getImage(_ name: String) -> ImageResource? { files[name].map { .init(path: $0) } }
    func getGifFile(_ name: String) -> URL? { files[name] }
}

enum ScriptWidgetFetchPolicy {
    static func validationError(for url: URL) -> String? {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil ? nil : "Unsupported image URL"
    }
}

enum ScriptWidgetFetchManager { static let maximumResponseBytes = 1_024 * 1_024 }

/// Bounded extension image transport; no package registry, JSC or process-global
/// credential state. The native upstream downsampling/cache path stays intact.
enum HanlinWidgetImageTransport {
    private final class Transfer: NSObject, URLSessionDataDelegate {
        struct State: Sendable { var data = Data(); var rejected = false; var status = 0; var headers: [String: String] = [:] }
        let state = Mutex(State())
        let done = DispatchSemaphore(value: 0)
        let acceptHTTPFailures: Bool
        init(acceptHTTPFailures: Bool) { self.acceptHTTPFailures = acceptHTTPFailures }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            let accepted = response.expectedContentLength <= ScriptWidgetFetchManager.maximumResponseBytes
                && (response as? HTTPURLResponse).map { acceptHTTPFailures || (200..<300).contains($0.statusCode) } == true
            if !accepted { state.withLock { $0.rejected = true } }
            if let http = response as? HTTPURLResponse {
                state.withLock { value in
                    value.status = http.statusCode
                    for name in ["content-type", "cache-control", "expires", "last-modified", "date", "retry-after"] {
                        if let header = http.value(forHTTPHeaderField: name), header.utf8.count <= 2_048 { value.headers[name] = header }
                    }
                }
            }
            completionHandler(accepted ? .allow : .cancel)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let accepted = state.withLock { value in
                guard data.count <= ScriptWidgetFetchManager.maximumResponseBytes - value.data.count else { value.rejected = true; return false }
                value.data.append(data)
                return true
            }
            if !accepted { dataTask.cancel() }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if error != nil { state.withLock { $0.rejected = true } }
            done.signal()
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(request.url.flatMap { ScriptWidgetFetchPolicy.validationError(for: $0) == nil ? request : nil })
        }
    }

    static func fetch(_ url: URL, timeout: TimeInterval) -> Data? {
        guard ScriptWidgetFetchPolicy.validationError(for: url) == nil else { return nil }
        return request(URLRequest(url: url), timeout: timeout, acceptHTTPFailures: false)?.data
    }

    struct Response: Sendable { let data: Data; let status: Int; let headers: [String: String] }
    static func request(_ request: URLRequest, timeout: TimeInterval, acceptHTTPFailures: Bool = true) -> Response? {
        guard timeout.isFinite, timeout > 0, let url = request.url, ScriptWidgetFetchPolicy.validationError(for: url) == nil,
              (request.httpBody?.count ?? 0) <= 1_024 * 1_024 else { return nil }
        let transfer = Transfer(acceptHTTPFailures: acceptHTTPFailures)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request).resume()
        guard transfer.done.wait(timeout: .now() + timeout) == .success else { return nil }
        return transfer.state.withLock { $0.rejected ? nil : Response(data: $0.data, status: $0.status, headers: $0.headers) }
    }
}
