import Foundation
import HanlinScriptContracts

public enum HanlinArchiveEntryKind: String, Codable, Hashable, Sendable {
    case file
    case directory
    case symbolicLink
    case hardLink
}

public struct HanlinArchiveEntryMetadata: Codable, Hashable, Sendable {
    public let path: String
    public let kind: HanlinArchiveEntryKind
    public let compressedBytes: Int64
    public let uncompressedBytes: Int64

    public init(
        path: String,
        kind: HanlinArchiveEntryKind,
        compressedBytes: Int64,
        uncompressedBytes: Int64
    ) {
        self.path = path
        self.kind = kind
        self.compressedBytes = compressedBytes
        self.uncompressedBytes = uncompressedBytes
    }
}

public struct HanlinArchiveLimits: Codable, Hashable, Sendable {
    public let maximumArchiveBytes: Int64
    public let maximumFiles: Int
    public let maximumDirectories: Int
    public let maximumDepth: Int
    public let maximumUncompressedBytes: Int64
    public let maximumCompressionRatio: Int64

    public init(
        maximumArchiveBytes: Int64 = 64 * 1_048_576,
        maximumFiles: Int = 4_096,
        maximumDirectories: Int = 1_024,
        maximumDepth: Int = 24,
        maximumUncompressedBytes: Int64 = 256 * 1_048_576,
        maximumCompressionRatio: Int64 = 100
    ) {
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumFiles = maximumFiles
        self.maximumDirectories = maximumDirectories
        self.maximumDepth = maximumDepth
        self.maximumUncompressedBytes = maximumUncompressedBytes
        self.maximumCompressionRatio = maximumCompressionRatio
    }

    public static let packageImport = HanlinArchiveLimits()
}

public struct HanlinArchivePolicy: Sendable {
    public let limits: HanlinArchiveLimits

    public init(limits: HanlinArchiveLimits = .packageImport) {
        self.limits = limits
    }

    public func inspect(
        entries: [HanlinArchiveEntryMetadata],
        centralDirectoryEntryCount: Int,
        archiveBytes: Int64
    ) -> HanlinArchiveInspection {
        var findings: [HanlinArchiveFinding] = []
        var ignored: [String] = []
        var normalizedPaths: [String] = []
        var fileCount = 0
        var directoryCount = 0
        var uncompressedBytes: Int64 = 0
        var compressedBytes: Int64 = 0
        var maximumDepth = 0
        var canonicalPaths: [String: String] = [:]
        var caseFoldedPaths: [String: String] = [:]

        if archiveBytes > limits.maximumArchiveBytes {
            findings.append(.init(
                code: .compressedSizeLimit,
                severity: .error,
                message: "Archive byte count exceeds the configured limit."
            ))
        }
        if entries.count != centralDirectoryEntryCount {
            findings.append(.init(
                code: .encryptedEntry,
                severity: .error,
                message: "The central directory contains unreadable or encrypted entries."
            ))
        }

        for entry in entries {
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            if Self.isIgnored(path) {
                ignored.append(path)
                continue
            }
            if path.contains("\0") {
                findings.append(finding(.nulByte, path, "Archive path contains a NUL byte."))
                continue
            }
            if path.hasPrefix("/") || path.hasPrefix("\\") {
                findings.append(finding(.absolutePath, path, "Absolute archive paths are forbidden."))
            }
            if Self.hasDrivePrefix(path) {
                findings.append(finding(.drivePrefix, path, "Windows drive-prefixed paths are forbidden."))
            }
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            if components.contains("..") {
                findings.append(finding(.parentTraversal, path, "Parent traversal is forbidden."))
            }
            let canonicalComponents = path.hasSuffix("/") ? components.dropLast() : components[...]
            if canonicalComponents.contains(where: { $0.isEmpty || $0 == "." }) {
                findings.append(finding(
                    .parentTraversal,
                    path,
                    "Empty and current-directory path components are forbidden."
                ))
            }
            let effectiveComponents = components.filter { !$0.isEmpty && $0 != "." }
            maximumDepth = max(maximumDepth, effectiveComponents.count)
            if effectiveComponents.count > limits.maximumDepth {
                findings.append(finding(.depthLimit, path, "Archive nesting depth exceeds policy."))
            }
            switch entry.kind {
            case .file:
                fileCount += 1
                if !Self.isAllowedFile(path) {
                    findings.append(finding(
                        .unsupportedFileType,
                        path,
                        "The archive contains a file type that packages cannot install."
                    ))
                }
            case .directory:
                directoryCount += 1
            case .symbolicLink:
                findings.append(finding(.symbolicLink, path, "Symbolic links are forbidden."))
            case .hardLink:
                findings.append(finding(.hardLink, path, "Hard links are forbidden."))
            }
            compressedBytes = Self.adding(entry.compressedBytes, to: compressedBytes)
            uncompressedBytes = Self.adding(entry.uncompressedBytes, to: uncompressedBytes)
            if entry.uncompressedBytes > 0 {
                if entry.compressedBytes == 0
                    || entry.uncompressedBytes / max(1, entry.compressedBytes) > limits.maximumCompressionRatio
                {
                    findings.append(finding(
                        .compressionRatioLimit,
                        path,
                        "Entry compression ratio exceeds policy."
                    ))
                }
            }

            let unicodeKey = path.precomposedStringWithCanonicalMapping
            if let existing = canonicalPaths[unicodeKey] {
                findings.append(finding(
                    .unicodeCollision,
                    path,
                    existing == path
                        ? "Archive contains a duplicate path."
                        : "Path collides with '\(existing)' after Unicode normalization."
                ))
            } else {
                canonicalPaths[unicodeKey] = path
            }
            let caseKey = unicodeKey.lowercased(with: Locale(identifier: "en_US_POSIX"))
            if let existing = caseFoldedPaths[caseKey], existing != path {
                findings.append(finding(
                    .caseCollision,
                    path,
                    "Path collides with '\(existing)' on a case-insensitive file system."
                ))
            } else {
                caseFoldedPaths[caseKey] = path
            }
            normalizedPaths.append(path)
        }

        if fileCount > limits.maximumFiles {
            findings.append(.init(
                code: .fileCountLimit,
                severity: .error,
                message: "Archive file count exceeds policy."
            ))
        }
        if directoryCount > limits.maximumDirectories {
            findings.append(.init(
                code: .fileCountLimit,
                severity: .error,
                message: "Archive directory count exceeds policy."
            ))
        }
        if uncompressedBytes > limits.maximumUncompressedBytes {
            findings.append(.init(
                code: .uncompressedSizeLimit,
                severity: .error,
                message: "Expanded archive size exceeds policy."
            ))
        }

        let manifests = normalizedPaths.filter {
            $0 == "script.json" || $0.hasSuffix("/script.json")
        }
        let manifestPath = manifests.count == 1 ? manifests[0] : nil
        if manifests.count != 1 {
            findings.append(.init(
                code: .ambiguousManifest,
                severity: .error,
                message: manifests.isEmpty
                    ? "Archive does not contain script.json."
                    : "Archive contains more than one script.json."
            ))
        }
        let wrapper = manifestPath.flatMap(Self.wrapperDirectory(for:))
        if let wrapper,
           normalizedPaths.contains(where: {
               $0 != wrapper && !$0.hasPrefix("\(wrapper)/")
           })
        {
            findings.append(.init(
                code: .ambiguousManifest,
                severity: .error,
                message: "Entries exist outside the package wrapper directory."
            ))
        }

        return HanlinArchiveInspection(
            fileCount: fileCount,
            directoryCount: directoryCount,
            compressedBytes: compressedBytes,
            uncompressedBytes: uncompressedBytes,
            maximumDepth: maximumDepth,
            wrapperDirectory: wrapper,
            manifestPath: manifestPath,
            ignoredEntries: ignored.sorted(),
            findings: findings
        )
    }

    public static func normalizedRelativePath(_ value: String) -> String? {
        var path = value.replacingOccurrences(of: "\\", with: "/")
        if path.hasSuffix("/") {
            path.removeLast()
        }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0"),
              !hasDrivePrefix(path)
        else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains(where: { $0.isEmpty }) else {
            return nil
        }
        let normalized = components.filter { $0 != "." }.joined(separator: "/")
        return normalized.isEmpty ? nil : normalized.precomposedStringWithCanonicalMapping
    }

    private static func wrapperDirectory(for manifestPath: String) -> String? {
        let components = manifestPath.split(separator: "/")
        return components.count == 2 ? String(components[0]) : nil
    }

    private static func hasDrivePrefix(_ path: String) -> Bool {
        let scalars = Array(path.unicodeScalars.prefix(3))
        guard scalars.count >= 2 else { return false }
        return CharacterSet.letters.contains(scalars[0]) && scalars[1].value == 58
    }

    private static func isIgnored(_ path: String) -> Bool {
        path == "__MACOSX" || path.hasPrefix("__MACOSX/")
            || path.split(separator: "/").last?.hasPrefix("._") == true
    }

    private static func isAllowedFile(_ path: String) -> Bool {
        let allowed: Set<String> = [
            "ts", "tsx", "js", "jsx", "json", "md", "txt", "strings",
            "css", "html", "svg", "png", "jpg", "jpeg", "gif", "webp",
            "heic", "pdf", "plist", "m4a", "mp3", "wav", "mp4", "mov"
        ]
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: ".") else { return false }
        return allowed.contains(name[name.index(after: dot)...].lowercased())
    }

    private static func adding(_ value: Int64, to total: Int64) -> Int64 {
        guard value >= 0, total <= Int64.max - value else { return Int64.max }
        return total + value
    }

    private func finding(
        _ code: HanlinArchiveFindingCode,
        _ entry: String,
        _ message: String
    ) -> HanlinArchiveFinding {
        .init(code: code, severity: .error, entry: entry, message: message)
    }
}
