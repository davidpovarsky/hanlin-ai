#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import Foundation
import ImageIO
import UniformTypeIdentifiers
import HanlinPresentationKit

/// The existing bounded citation thumbnail path is shared with declared tool
/// artwork. URLSession retains its existing HTTP cache; decoding stays off the
/// main actor and returns only a small PNG, never executable image content.
enum HanlinIconThumbnailLoader {
    static func png(from url: URL) async throws -> Data? {
        guard let url = HanlinToolIcon.safeURL(url.absoluteString) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: HanlinIconRedirectPolicy())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = response.url,
              HanlinToolIcon.safeURL(finalURL.absoluteString) != nil else { return nil }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 131_072 else { throw CocoaError(.fileReadTooLarge) }
            data.append(byte)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let icon = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceShouldCacheImmediately: false,
              ] as CFDictionary) else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, icon, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return png as Data
    }
}

private final class HanlinIconRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, HanlinToolIcon.safeURL(url.absoluteString) != nil else {
            completionHandler(nil)
            return
        }
        var next = request
        next.httpShouldHandleCookies = false
        completionHandler(next)
    }
}
#endif
