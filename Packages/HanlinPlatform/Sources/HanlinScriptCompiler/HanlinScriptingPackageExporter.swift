import Foundation
import ZIPFoundation

public enum HanlinScriptingPackageExporterError: Error, Equatable, Sendable {
    case invalidPackageRoot
    case destinationExists
    case unsafeSourcePath(String)
}

public struct HanlinScriptingPackageExporter: Sendable {
    private var fileManager: FileManager { .default }

    public init() {}

    public func exportPackage(
        at packageRoot: URL,
        to destination: URL,
        wrapperDirectory: String? = nil
    ) throws {
        let manifestURL = packageRoot.appending(path: "script.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)),
              ["scripting", "zip"].contains(destination.pathExtension.lowercased())
        else {
            throw HanlinScriptingPackageExporterError.invalidPackageRoot
        }
        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw HanlinScriptingPackageExporterError.destinationExists
        }
        let wrapper = try normalizedWrapper(wrapperDirectory ?? packageRoot.lastPathComponent)
        // Temporary-directory URLs on Apple platforms can mix the `/var` and
        // `/private/var` spellings for the same location. Resolve that system
        // alias before enforcing package-root containment.
        let rootPath = packageRoot
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path(percentEncoded: false)
        guard let enumerator = fileManager.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HanlinScriptingPackageExporterError.invalidPackageRoot
        }
        var files: [(path: String, url: URL)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else {
                throw HanlinScriptingPackageExporterError.unsafeSourcePath(url.lastPathComponent)
            }
            guard values.isRegularFile == true else { continue }
            let path = url
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path(percentEncoded: false)
            guard path.hasPrefix(rootPath + "/") else {
                throw HanlinScriptingPackageExporterError.unsafeSourcePath(url.lastPathComponent)
            }
            let relative = String(path.dropFirst(rootPath.count + 1))
                .replacingOccurrences(of: "\\", with: "/")
                .precomposedStringWithCanonicalMapping
            guard let normalized = HanlinArchivePolicy.normalizedRelativePath(relative) else {
                throw HanlinScriptingPackageExporterError.unsafeSourcePath(relative)
            }
            files.append(("\(wrapper)/\(normalized)", url))
        }
        let archive = try Archive(url: destination, accessMode: .create)
        for file in files.sorted(by: { $0.path < $1.path }) {
            let data = try Data(contentsOf: file.url, options: .mappedIfSafe)
            try archive.addEntry(
                with: file.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    let end = min(start + size, data.count)
                    return data.subdata(in: start ..< end)
                }
            )
        }
    }

    private func normalizedWrapper(_ value: String) throws -> String {
        guard let normalized = HanlinArchivePolicy.normalizedRelativePath(value),
              !normalized.contains("/") else {
            throw HanlinScriptingPackageExporterError.unsafeSourcePath(value)
        }
        return normalized
    }
}
