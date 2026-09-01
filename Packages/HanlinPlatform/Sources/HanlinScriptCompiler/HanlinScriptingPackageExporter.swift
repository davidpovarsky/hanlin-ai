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
            let depth = enumerator.level
            guard depth > 0, url.pathComponents.count >= depth else {
                throw HanlinScriptingPackageExporterError.unsafeSourcePath(url.lastPathComponent)
            }
            // DirectoryEnumerator only yields descendants of packageRoot. Its
            // level remains stable even when iOS represents the same sandbox
            // once as `/var/...` and once as `/private/var/...`.
            let relative = url.pathComponents.suffix(depth).joined(separator: "/")
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
