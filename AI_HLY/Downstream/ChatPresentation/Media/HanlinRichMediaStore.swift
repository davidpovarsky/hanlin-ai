#if HANLIN_A2UI_POC && canImport(UIKit)
import Foundation
import Darwin
import ImageIO
import UniformTypeIdentifiers
import SwiftSoup

/// Bounded, on-demand retrieval for the custom gallery and source card. The
/// official A2UI Image/Video/Audio builders remain their original implementations.
actor HanlinRichMediaStore {
    static let shared = HanlinRichMediaStore()

    struct ImageFile: Sendable {
        let url: URL
        let bytes: Int
        let created: Date
    }

    struct LinkMetadata: Sendable {
        let source: URL
        let title: String
        let summary: String
        let thumbnail: URL?
        let created: Date
    }

    enum Failure: Error {
        case invalidSource, privateAddress, unavailable, responseTooLarge
        case unsupportedContent, imageTooLarge, busy
    }

    private enum Kind: Hashable, Sendable { case image, document }
    private struct Request: Hashable, Sendable { let url: URL; let kind: Kind }
    private struct Pending: Sendable {
        let id: UUID
        let task: Task<Data, any Error>
        var consumers: Set<UUID>
    }
    private var pending: [Request: Pending] = [:]
    private var images: [URL: ImageFile] = [:]
    private var links: [URL: LinkMetadata] = [:]
    private let ttl: TimeInterval = 300
    private let maximumCacheBytes = 48 * 1024 * 1024
    private let maximumCacheEntries = 20
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "HanlinRichMedia", directoryHint: .isDirectory)

    private init() {
        // This actor is a singleton. A new process has no live preview lease from
        // its predecessor; remove only this feature's disposable cache.
        try? FileManager.default.removeItem(at: directory)
    }

    func image(for url: URL) async throws -> ImageFile {
        if let cached = images[url], Date().timeIntervalSince(cached.created) < ttl,
           FileManager.default.fileExists(atPath: cached.url.path) { return cached }
        let encoded = try await data(for: url, kind: .image)
        try Task.checkCancellation()
        // A concurrent caller may already have installed the identical result.
        if let cached = images[url], Date().timeIntervalSince(cached.created) < ttl,
           FileManager.default.fileExists(atPath: cached.url.path) { return cached }
        let thumbnail = try await Self.thumbnail(encoded)
        try Task.checkCancellation()
        evictImages(adding: thumbnail.count)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: UUID().uuidString + ".jpg")
        try thumbnail.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        let result = ImageFile(url: file, bytes: thumbnail.count, created: Date())
        images[url] = result
        return result
    }

    func metadata(for url: URL) async throws -> LinkMetadata {
        if let cached = links[url], Date().timeIntervalSince(cached.created) < ttl { return cached }
        let html = try await data(for: url, kind: .document)
        try Task.checkCancellation()
        let result = try await Self.parseMetadata(html, source: url)
        if links.count >= maximumCacheEntries,
           let oldest = links.min(by: { $0.value.created < $1.value.created })?.key {
            links.removeValue(forKey: oldest)
        }
        links[url] = result
        return result
    }

    private func data(for url: URL, kind: Kind) async throws -> Data {
        guard HanlinRemoteMediaURL(url.absoluteString) != nil else { throw Failure.invalidSource }
        let key = Request(url: url, kind: kind)
        let consumer = UUID()
        let request: Pending
        if var existing = pending[key] {
            existing.consumers.insert(consumer)
            pending[key] = existing
            request = existing
        } else {
            guard pending.count < 4 else { throw Failure.busy }
            request = Pending(id: UUID(), task: Task { try await Self.fetch(url, kind: kind) },
                              consumers: [consumer])
            pending[key] = request
        }
        defer { release(key, requestID: request.id, consumer: consumer) }
        return try await withTaskCancellationHandler {
            let result = try await request.task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            // URLSession is cancelled only when its final visible consumer leaves.
            Task { await self.release(key, requestID: request.id, consumer: consumer) }
        }
    }

    private func release(_ key: Request, requestID: UUID, consumer: UUID) {
        guard var request = pending[key], request.id == requestID,
              request.consumers.remove(consumer) != nil else { return }
        if request.consumers.isEmpty {
            request.task.cancel()
            pending.removeValue(forKey: key)
        } else { pending[key] = request }
    }

    private func evictImages(adding bytes: Int) {
        let now = Date()
        let expired = images.compactMap { now.timeIntervalSince($0.value.created) >= ttl ? $0.key : nil }
        for key in expired {
            if let entry = images.removeValue(forKey: key) { try? FileManager.default.removeItem(at: entry.url) }
        }
        while images.count >= maximumCacheEntries ||
            images.values.reduce(0, { $0 + $1.bytes }) + bytes > maximumCacheBytes {
            guard let oldest = images.min(by: { $0.value.created < $1.value.created })?.key,
                  let entry = images.removeValue(forKey: oldest) else { break }
            try? FileManager.default.removeItem(at: entry.url)
        }
    }

    @concurrent
    private static func fetch(_ url: URL, kind: Kind) async throws -> Data {
        guard let host = url.host else { throw Failure.invalidSource }
        // getaddrinfo is blocking; isolate that work from the cooperative executor.
        let resolution = Task.detached(priority: .utility) { try requirePublicHost(host) }
        try await withTaskCancellationHandler {
            try await resolution.value
        } onCancel: { resolution.cancel() }
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration,
                                 delegate: HanlinMediaNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue(kind == .image ? "image/jpeg,image/png,image/webp,image/heic,image/gif" : "text/html,application/xhtml+xml",
                         forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        let limit = kind == .image ? 4 * 1024 * 1024 : 1024 * 1024
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == url else { throw Failure.unavailable }
        guard response.expectedContentLength <= Int64(limit) else { throw Failure.responseTooLarge }
        let mime = response.mimeType?.lowercased() ?? ""
        let permitted = kind == .image
            ? ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif", "image/gif"].contains(mime)
            : ["text/html", "application/xhtml+xml"].contains(mime)
        guard permitted else { throw Failure.unsupportedContent }
        var result = Data()
        result.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if result.count % 1024 == 0 { try Task.checkCancellation() }
            guard result.count < limit else { throw Failure.responseTooLarge }
            result.append(byte)
        }
        return result
    }

    @concurrent
    private static func thumbnail(_ data: Data) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= 20_000, height <= 20_000,
              width <= 20_000_000 / height else { throw Failure.imageTooLarge }
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw Failure.unsupportedContent }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
            UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.unsupportedContent }
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 4 * 1024 * 1024
        else { throw Failure.imageTooLarge }
        return output as Data
    }

    @concurrent
    private static func parseMetadata(_ data: Data, source: URL) async throws -> LinkMetadata {
        // Reuse Hanlin's already-pinned HTML parser. It executes no page scripts
        // and fetches no linked resource while parsing these bounded bytes.
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self), source.absoluteString)
        let ogTitle = try document.select("meta[property=og:title]").first()?.attr("content")
        let title: String
        if let ogTitle, !ogTitle.isEmpty { title = ogTitle }
        else { title = try document.title() }
        let description = try document.select("meta[property=og:description]").first()?.attr("content")
            ?? document.select("meta[name=description]").first()?.attr("content") ?? ""
        let image = try document.select("meta[property=og:image]").first()?.attr("content")
        let imageURL = image.flatMap { URL(string: $0, relativeTo: source)?.absoluteURL }
            .flatMap { HanlinRemoteMediaURL($0.absoluteString)?.url }
        return LinkMetadata(source: source,
            title: String((title.isEmpty ? (source.host ?? "") : title).prefix(512)),
            summary: String(description.prefix(2048)), thumbnail: imageURL, created: Date())
    }

    /// Reject every resolved private/special address before URLSession starts.
    /// URLSession resolves independently: this is not DNS-rebinding pinning.
    private static func requirePublicHost(_ host: String) throws {
        try Task.checkCancellation()
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = Int32(IPPROTO_TCP)
        var first: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &first) == 0, let first else { throw Failure.unavailable }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        var found = false
        while let info = current {
            guard let address = info.pointee.ai_addr else { throw Failure.privateAddress }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                let raw = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                guard HanlinMediaAddressPolicy.publicIPv4(UInt32(bigEndian: raw)) else { throw Failure.privateAddress }
            case AF_INET6:
                let raw = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                let bytes = withUnsafeBytes(of: raw) { Array($0) }
                guard HanlinMediaAddressPolicy.publicIPv6(bytes) else { throw Failure.privateAddress }
            default: throw Failure.privateAddress
            }
            found = true
            current = info.pointee.ai_next
        }
        guard found else { throw Failure.unavailable }
        try Task.checkCancellation()
    }

}

/// Every redirect requires a new user-approved source; never forward cookies,
/// credentials or a signed source query to a redirect destination.
private final class HanlinMediaNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
#endif
