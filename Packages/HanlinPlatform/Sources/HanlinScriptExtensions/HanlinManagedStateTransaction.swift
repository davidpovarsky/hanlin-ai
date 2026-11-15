import Foundation

extension HanlinScriptExtensionStore {
    /// A fixed host-owned state file under this managed root. Reuses the existing
    /// no-follow traversal and interprocess transaction lock; never accepts a URL.
    /// Atomic replacement is process-crash recovery, not a power-loss guarantee.
    public func transactManagedState<Result>(
        fileName: String, maximumBytes: Int,
        _ operation: (inout Data?) throws -> Result
    ) throws -> Result {
        guard let first = fileName.utf8.first, (97...122).contains(first) || (48...57).contains(first),
              fileName.utf8.count <= 96, fileName.hasSuffix(".json"),
              fileName.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              maximumBytes > 0, maximumBytes <= 16_777_216 else {
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }
        return try withLock {
            let file = root.appending(path: fileName, directoryHint: .notDirectory)
            try rejectSymlinks(to: file)
            var original: Data?
            if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw HanlinScriptExtensionStoreError.invalidArtifactReference
                }
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var data = Data()
                while let part = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)), !part.isEmpty {
                    data.append(part)
                    guard data.count <= maximumBytes else { throw HanlinScriptExtensionStoreError.snapshotTooLarge }
                }
                original = data
            }
            var changed = original
            let result = try operation(&changed)
            guard let changed else {
                guard original == nil else { throw HanlinScriptExtensionStoreError.invalidCommit }
                return result // This API deliberately has no delete operation.
            }
            guard changed.count <= maximumBytes else { throw HanlinScriptExtensionStoreError.snapshotTooLarge }
            if changed != original {
                try rejectSymlinks(to: file, phase: .storeSave)
                try changed.write(to: file, options: .atomic)
                try rejectSymlinks(to: file)
                guard try Data(contentsOf: file) == changed else { throw HanlinScriptExtensionStoreError.invalidCommit }
            }
            return result
        }
    }
}
