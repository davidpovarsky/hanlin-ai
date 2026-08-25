import Foundation
import UniformTypeIdentifiers

public struct HanlinScriptingFetchRequest: Decodable, Sendable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let bodyBase64: String?
    public let timeout: Double?
    public let allowInsecureRequest: Bool
}

public struct HanlinScriptingFetchResponse: Sendable {
    public let url: String
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(url: String, status: Int, headers: [String: String], body: Data) {
        self.url = url
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public typealias HanlinScriptingNetworkLoader = @Sendable (
    HanlinScriptingFetchRequest
) async throws -> HanlinScriptingFetchResponse

public enum HanlinScriptingURLSessionLoader {
    public static func load(_ request: HanlinScriptingFetchRequest) async throws -> HanlinScriptingFetchResponse {
        guard let url = URL(string: request.url), let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && request.allowInsecureRequest) else {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "invalid_url",
                message: "The URL is malformed or its scheme is not permitted."
            )
        }
        guard request.method.utf8.count <= 32,
              request.headers.count <= 128,
              request.headers.allSatisfy({ $0.key.utf8.count <= 8_192 && $0.value.utf8.count <= 32_768 }) else {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "invalid_request",
                message: "The network request exceeds the supported limits."
            )
        }
        var nativeRequest = URLRequest(url: url)
        nativeRequest.httpMethod = request.method.uppercased()
        request.headers.forEach { nativeRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let bodyBase64 = request.bodyBase64 {
            guard let body = Data(base64Encoded: bodyBase64), body.count <= 16 * 1_024 * 1_024 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_body",
                    message: "The request body is not valid base64 data or is too large."
                )
            }
            nativeRequest.httpBody = body
        }
        if let timeout = request.timeout {
            guard timeout.isFinite, timeout > 0, timeout <= 300 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_timeout",
                    message: "The timeout must be between 0 and 300 seconds."
                )
            }
            nativeRequest.timeoutInterval = timeout
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (body, response) = try await session.data(for: nativeRequest)
            try Task.checkCancellation()
            guard body.count <= 16 * 1_024 * 1_024,
                  let httpResponse = response as? HTTPURLResponse else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_response",
                    message: "The network response is invalid or too large."
                )
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
                guard let name = item.key as? String else { return }
                result[name] = String(describing: item.value)
            }
            return HanlinScriptingFetchResponse(
                url: httpResponse.url?.absoluteString ?? request.url,
                status: httpResponse.statusCode,
                headers: headers,
                body: body
            )
        } catch is CancellationError {
            throw HanlinScriptingNativeError(
                name: "AbortError",
                code: "cancelled",
                message: "The operation was cancelled."
            )
        } catch let error as HanlinScriptingNativeError {
            throw error
        } catch {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "network_failure",
                message: "The network request failed."
            )
        }
    }
}

struct HanlinScriptingNativeError: Error, Sendable {
    let name: String
    let code: String
    let message: String
}

final class HanlinScriptingPackageFileSystem: @unchecked Sendable {
    private struct ResolvedPath {
        let url: URL
        let root: URL
        let readOnly: Bool
    }

    private let lock = NSLock()
    private let fileManager = FileManager()
    private let documentsRoot: URL
    private let appGroupRoot: URL
    private let temporaryRoot: URL
    private let scriptsRoot: URL
    private let allowed: Bool
    private let maximumBytes = 64 * 1_024 * 1_024
    private let maximumReadBytes = 16 * 1_024 * 1_024

    init(
        installedPackageID: String,
        allowed: Bool,
        runtimeRoot: URL?,
        packageSourceDirectory: URL?
    ) throws {
        let baseRoot: URL
        if let runtimeRoot {
            baseRoot = runtimeRoot
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "filesystem_unavailable",
                    message: "The package filesystem is unavailable."
                )
            }
            baseRoot = applicationSupport
                .appending(path: "Hanlin/ScriptingPlatform/RuntimeData", directoryHint: .isDirectory)
                .appending(path: installedPackageID, directoryHint: .isDirectory)
        }
        documentsRoot = baseRoot.appending(path: "Documents", directoryHint: .isDirectory)
        appGroupRoot = baseRoot.appending(path: "AppGroupDocuments", directoryHint: .isDirectory)
        temporaryRoot = baseRoot.appending(path: "Temporary", directoryHint: .isDirectory)
        scriptsRoot = packageSourceDirectory ?? baseRoot.appending(path: "Scripts", directoryHint: .isDirectory)
        self.allowed = allowed
        try fileManager.createDirectory(at: documentsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        if packageSourceDirectory == nil {
            try fileManager.createDirectory(at: scriptsRoot, withIntermediateDirectories: true)
        }
    }

    var publicDirectories: [String: Any] {
        [
            "documentsDirectory": "/documents",
            "appGroupDocumentsDirectory": "/app-group",
            "temporaryDirectory": "/temporary",
            "scriptsDirectory": "/scripts",
            "isiCloudEnabled": false,
            "isWebDAVAvailable": false,
        ]
    }

    func perform(operation: String, payload: [String: Any]) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        guard allowed else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "permission_denied",
                message: "The files capability is not granted."
            )
        }
        switch operation {
        case "file.createDirectory":
            let target = try writable(payload, "path")
            let recursive = payload["recursive"] as? Bool ?? false
            try fileManager.createDirectory(
                at: target.url,
                withIntermediateDirectories: recursive
            )
            return NSNull()
        case "file.readDirectory":
            let target = try readable(payload, "path")
            let recursive = payload["recursive"] as? Bool ?? false
            return try directoryContents(at: target.url, recursive: recursive)
        case "file.exists":
            return fileManager.fileExists(atPath: try resolved(payload, "path").url.path())
        case "file.isFile":
            return try fileType(payload) == .typeRegular
        case "file.isDirectory":
            return try fileType(payload) == .typeDirectory
        case "file.isLink":
            return try fileType(payload, followsLinks: false) == .typeSymbolicLink
        case "file.readData":
            let data = try readData(payload)
            return data.base64EncodedString()
        case "file.writeData":
            let target = try writable(payload, "path")
            guard let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64), data.count <= maximumReadBytes else {
                throw invalid("The file data is invalid or too large.")
            }
            try checkQuota(replacing: target.url, withByteCount: data.count)
            try data.write(to: target.url, options: .atomic)
            return NSNull()
        case "file.appendData":
            let target = try writable(payload, "path")
            guard let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64), data.count <= maximumReadBytes else {
                throw invalid("The file data is invalid or too large.")
            }
            try fileManager.createDirectory(
                at: target.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let previous = (try? Data(contentsOf: target.url, options: .mappedIfSafe)) ?? Data()
            guard previous.count + data.count <= maximumReadBytes else {
                throw quota()
            }
            try checkQuota(replacing: target.url, withByteCount: previous.count + data.count)
            var combined = previous
            combined.append(data)
            try combined.write(to: target.url, options: .atomic)
            return NSNull()
        case "file.stat":
            return try stat(payload)
        case "file.remove":
            let target = try writable(payload, "path")
            try fileManager.removeItem(at: target.url)
            return NSNull()
        case "file.copy":
            let source = try readable(payload, "path")
            let destination = try writable(payload, "newPath")
            try checkQuota(replacing: destination.url, withByteCount: try recursiveSize(source.url))
            try fileManager.copyItem(at: source.url, to: destination.url)
            return NSNull()
        case "file.rename":
            let source = try writable(payload, "path")
            let destination = try writable(payload, "newPath")
            try fileManager.moveItem(at: source.url, to: destination.url)
            return NSNull()
        case "file.mimeType":
            let target = try readable(payload, "path")
            return UTType(filenameExtension: target.url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
        default:
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "unsupported_operation",
                message: "The requested filesystem operation is unavailable."
            )
        }
    }

    private func readData(_ payload: [String: Any]) throws -> Data {
        let target = try readable(payload, "path")
        let attributes = try fileManager.attributesOfItem(atPath: target.url.path())
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maximumReadBytes else {
            throw quota()
        }
        return try Data(contentsOf: target.url, options: .mappedIfSafe)
    }

    private func directoryContents(at url: URL, recursive: Bool) throws -> [String] {
        if !recursive {
            return try fileManager.contentsOfDirectory(atPath: url.path()).sorted()
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [String] = []
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            result.append(String(item.path().dropFirst(url.path().count + 1)))
        }
        return result.sorted()
    }

    private func stat(_ payload: [String: Any]) throws -> [String: Any] {
        let target = try readable(payload, "path")
        let attributes = try fileManager.attributesOfItem(atPath: target.url.path())
        let type = attributes[.type] as? FileAttributeType
        return [
            "creationDate": milliseconds(attributes[.creationDate] as? Date),
            "modificationDate": milliseconds(attributes[.modificationDate] as? Date),
            "type": typeName(type),
            "size": (attributes[.size] as? NSNumber)?.int64Value ?? 0,
        ]
    }

    private func fileType(
        _ payload: [String: Any],
        followsLinks: Bool = true
    ) throws -> FileAttributeType? {
        guard let path = payload["path"] as? String else {
            throw invalid("A file path is required.")
        }
        let target = try resolve(
            path,
            requireExisting: false,
            followFinalSymbolicLink: followsLinks
        )
        guard fileManager.fileExists(atPath: target.url.path()) else { return nil }
        return try fileManager.attributesOfItem(atPath: target.url.path())[.type] as? FileAttributeType
    }

    private func checkQuota(replacing target: URL, withByteCount byteCount: Int) throws {
        let existing = (try? recursiveSize(target)) ?? 0
        let total = try recursiveSize(documentsRoot)
            + recursiveSize(appGroupRoot)
            + recursiveSize(temporaryRoot)
            - existing
            + byteCount
        guard total <= maximumBytes else { throw quota() }
    }

    private func recursiveSize(_ url: URL) throws -> Int {
        guard fileManager.fileExists(atPath: url.path()) else { return 0 }
        let attributes = try fileManager.attributesOfItem(atPath: url.path())
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
        }
        return total
    }

    private func readable(_ payload: [String: Any], _ key: String) throws -> ResolvedPath {
        let value = try resolved(payload, key)
        guard fileManager.fileExists(atPath: value.url.path()) else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "not_found",
                message: "The file or directory does not exist."
            )
        }
        return value
    }

    private func writable(_ payload: [String: Any], _ key: String) throws -> ResolvedPath {
        let value = try resolved(payload, key, requireExisting: false)
        guard !value.readOnly else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "read_only",
                message: "The scripts directory is read-only."
            )
        }
        return value
    }

    private func resolved(
        _ payload: [String: Any],
        _ key: String,
        requireExisting: Bool = true
    ) throws -> ResolvedPath {
        guard let path = payload[key] as? String else { throw invalid("A file path is required.") }
        return try resolve(path, requireExisting: requireExisting)
    }

    private func resolve(
        _ path: String,
        requireExisting: Bool,
        followFinalSymbolicLink: Bool = true
    ) throws -> ResolvedPath {
        guard !path.isEmpty, path.utf8.count <= 8_192,
              !path.contains("\\"), !path.contains("\0") else {
            throw invalid("The file path is invalid.")
        }
        let mapping: (root: URL, relative: String, readOnly: Bool)
        if path == "/documents" || path.hasPrefix("/documents/") {
            mapping = (documentsRoot, String(path.dropFirst("/documents".count)), false)
        } else if path == "/app-group" || path.hasPrefix("/app-group/") {
            mapping = (appGroupRoot, String(path.dropFirst("/app-group".count)), false)
        } else if path == "/temporary" || path.hasPrefix("/temporary/") {
            mapping = (temporaryRoot, String(path.dropFirst("/temporary".count)), false)
        } else if path == "/scripts" || path.hasPrefix("/scripts/") {
            mapping = (scriptsRoot, String(path.dropFirst("/scripts".count)), true)
        } else if !path.hasPrefix("/") {
            mapping = (documentsRoot, path, false)
        } else {
            throw invalid("The file path is outside the package filesystem.")
        }
        let components = mapping.relative.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), !components.contains(".") else {
            throw invalid("The file path contains traversal components.")
        }
        let candidate = components.reduce(mapping.root) {
            $0.appending(path: String($1), directoryHint: .inferFromPath)
        }.standardizedFileURL
        let candidateExists = fileManager.fileExists(atPath: candidate.path())
        let checkedURL = if followFinalSymbolicLink && (requireExisting || candidateExists) {
            candidate.resolvingSymlinksInPath()
        } else {
            candidate.deletingLastPathComponent().resolvingSymlinksInPath()
                .appending(path: candidate.lastPathComponent, directoryHint: .inferFromPath)
        }
        let root = mapping.root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path().hasSuffix("/") ? root.path() : root.path() + "/"
        guard checkedURL == root || checkedURL.path().hasPrefix(rootPath) else {
            throw invalid("The file path escapes its package root.")
        }
        return ResolvedPath(url: checkedURL, root: root, readOnly: mapping.readOnly)
    }

    private func milliseconds(_ date: Date?) -> Double {
        (date?.timeIntervalSince1970 ?? 0) * 1_000
    }

    private func typeName(_ type: FileAttributeType?) -> String {
        switch type {
        case .typeRegular: "file"
        case .typeDirectory: "directory"
        case .typeSymbolicLink: "link"
        case .typeSocket: "unixDomainSock"
        default: "notFound"
        }
    }

    private func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "Error", code: "invalid_path", message: message)
    }

    private func quota() -> HanlinScriptingNativeError {
        .init(name: "Error", code: "quota_exceeded", message: "The package file quota was exceeded.")
    }
}

enum HanlinScriptingNativeJSON {
    static func decodeObject(_ json: String) throws -> [String: Any] {
        guard json.utf8.count <= 20 * 1_024 * 1_024,
              let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "invalid_payload",
                message: "The native request payload is invalid."
            )
        }
        return object
    }

    static func success(_ value: Any) -> String {
        encode(["ok": true, "value": value])
    }

    static func failure(_ error: Error) -> String {
        let native = error as? HanlinScriptingNativeError ?? .init(
            name: "Error",
            code: "native_failure",
            message: "The native operation failed."
        )
        return encode([
            "ok": false,
            "error": ["name": native.name, "code": native.code, "message": native.message],
        ])
    }

    private static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"error":{"name":"Error","code":"encoding_failure","message":"The native result could not be encoded."}}"#
        }
        return string
    }
}
