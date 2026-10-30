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
        struct State: Sendable { var data = Data(); var rejected = false }
        let state = Mutex(State())
        let done = DispatchSemaphore(value: 0)
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            let accepted = response.expectedContentLength <= ScriptWidgetFetchManager.maximumResponseBytes
                && (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true
            if !accepted { state.withLock { $0.rejected = true } }
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
    }

    static func fetch(_ url: URL, timeout: TimeInterval) -> Data? {
        guard ScriptWidgetFetchPolicy.validationError(for: url) == nil else { return nil }
        let transfer = Transfer()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: url).resume()
        guard transfer.done.wait(timeout: .now() + timeout) == .success else { return nil }
        return transfer.state.withLock { $0.rejected ? nil : $0.data }
    }
}
