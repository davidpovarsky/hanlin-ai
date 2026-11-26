import Foundation

/// Source projects live outside installed, immutable package generations.
/// Coordination and compare-before-save protect edits made in another window or
/// by an iCloud/File Provider writer. A conflict never overwrites either version.
struct MiniAppsDeveloperWorkspace: Sendable {
    struct Entry: Identifiable, Hashable, Sendable {
        let path: String
        let name: String
        let isDirectory: Bool
        var id: String { path }
    }

    struct FolderStyle: Codable, Hashable, Sendable {
        var schemaVersion = 1
        var symbol = "folder"
        var color = "blue"
    }

    struct Document: Sendable {
        let path: String
        let text: String
        let original: Data
    }

    enum Failure: LocalizedError, Equatable {
        case invalidPath, symbolicLink, alreadyExists, changedOnDisk, unsupportedText, unsupportedMetadata
        var errorDescription: String? {
            switch self {
            case .invalidPath: "Choose a path inside this workspace."
            case .symbolicLink: "This file is a symbolic link. Open its original project instead."
            case .alreadyExists: "A file or folder already exists at that destination."
            case .changedOnDisk: "This file changed in another window or on another device. Reload it or save your draft as a new file."
            case .unsupportedText: "This file is not UTF-8 text."
            case .unsupportedMetadata: "This folder was saved by a newer version of MiniApps."
            }
        }
    }

    let root: URL

    init(root: URL) throws {
        guard root.isFileURL else { throw Failure.invalidPath }
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func url(for relative: String, allowRoot: Bool = false) throws -> URL {
        if allowRoot && (relative.isEmpty || relative == ".") { return root }
        guard !relative.contains("\0"), !relative.hasPrefix("/"),
              (allowRoot || !relative.isEmpty),
              !relative.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { throw Failure.invalidPath }
        let target = root.appending(path: relative).standardizedFileURL
        guard (allowRoot && target.path == root.path) || target.path.hasPrefix(root.path + "/") else { throw Failure.invalidPath }
        var current = root
        for component in target.pathComponents.dropFirst(root.pathComponents.count) {
            current.append(path: component)
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw Failure.symbolicLink
            }
        }
        guard target.resolvingSymlinksInPath().path == target.path else { throw Failure.symbolicLink }
        return target
    }

    func entries(in directory: String = "") throws -> [Entry] {
        let folder = try url(for: directory, allowRoot: true)
        let entries = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        return try entries.map { child in
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw Failure.symbolicLink }
            let relative = String(child.path.dropFirst(root.path.count + 1))
            return Entry(path: relative, name: child.lastPathComponent, isDirectory: values.isDirectory == true)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func sourceFiles(in directory: String = "") throws -> [Entry] {
        var files: [Entry] = []
        for entry in try entries(in: directory) {
            if entry.isDirectory {
                if !["node_modules", ".git", ".hanlin-build", ".hanlin-authoring"].contains(entry.name) {
                    files += try sourceFiles(in: entry.path)
                }
            } else {
                files.append(entry)
            }
        }
        return files
    }

    func read(_ relative: String) throws -> Document {
        let file = try url(for: relative)
        return try coordinateRead(file) { coordinated in
            let bytes = try Data(contentsOf: coordinated)
            guard let text = String(data: bytes, encoding: .utf8) else { throw Failure.unsupportedText }
            return Document(path: relative, text: text, original: bytes)
        }
    }

    func save(_ text: String, document: Document) throws -> Document {
        let file = try url(for: document.path)
        let bytes = Data(text.utf8)
        try coordinateWrite(file) { coordinated in
            guard try Data(contentsOf: coordinated) == document.original else { throw Failure.changedOnDisk }
            // Foundation's atomic replacement keeps the original file's
            // creation metadata, Finder label/color and comments with options [].
            let replacement = coordinated.deletingLastPathComponent()
                .appending(path: ".miniapps-save-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: replacement) }
            try bytes.write(to: replacement, options: .withoutOverwriting)
            _ = try FileManager.default.replaceItemAt(coordinated, withItemAt: replacement,
                backupItemName: nil, options: [])
        }
        return Document(path: document.path, text: text, original: bytes)
    }

    func createFile(_ relative: String, text: String = "") throws {
        let file = try url(for: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Do not silently replace a file that appeared between the UI and save.
        try coordinateWrite(file) { target in
            try Data(text.utf8).write(to: target, options: .withoutOverwriting)
        }
    }

    func createFolder(_ relative: String) throws {
        let folder = try url(for: relative)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw Failure.alreadyExists }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func move(_ source: String, to destination: String) throws {
        let sourceURL = try url(for: source)
        let destinationURL = try url(for: destination)
        guard !destinationURL.path.hasPrefix(sourceURL.path + "/"),
              !FileManager.default.fileExists(atPath: destinationURL.path) else { throw Failure.alreadyExists }
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if canImport(Darwin)
        var error: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: sourceURL, options: .forMoving,
            writingItemAt: destinationURL, options: [], error: &error) { from, to in
            result = Result { try FileManager.default.moveItem(at: from, to: to) }
        }
        if let error { throw error }
        guard let result else { throw Failure.invalidPath }
        try result.get()
        #else
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        #endif
    }

    func style(for directory: String) throws -> FolderStyle {
        _ = try url(for: directory, allowRoot: true)
        let file = try url(for: directory.isEmpty ? ".miniapps-folder.json" : directory + "/.miniapps-folder.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return FolderStyle() }
        let style = try coordinateRead(file) { target in
            try JSONDecoder().decode(FolderStyle.self, from: Data(contentsOf: target))
        }
        guard style.schemaVersion == 1 else { throw Failure.unsupportedMetadata }
        return style
    }

    func setStyle(_ style: FolderStyle, for directory: String) throws {
        _ = try url(for: directory, allowRoot: true)
        let file = try url(for: directory.isEmpty ? ".miniapps-folder.json" : directory + "/.miniapps-folder.json")
        guard style.schemaVersion == 1 else { throw Failure.unsupportedMetadata }
        try coordinateWrite(file) { target in
            try JSONEncoder().encode(style).write(to: target, options: .atomic)
        }
    }

    /// Copy, then build, an SDK example. Its original SDK location is never edited.
    func copyProject(from source: URL, named name: String, into directory: String = "") throws -> String {
        let relative = directory.isEmpty ? name : directory + "/" + name
        let target = try url(for: relative)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw Failure.alreadyExists }
        guard try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw Failure.invalidPath }
        let original = try MiniAppsDeveloperWorkspace(root: source)
        func copy(_ from: URL, _ to: URL) throws {
            guard !FileManager.default.fileExists(atPath: to.path) else { throw Failure.alreadyExists }
            // Check hidden files too; a copied link must not reintroduce a path
            // outside the user's independent project.
            var enumerationError: Error?
            guard let contents = FileManager.default.enumerator(at: from,
                includingPropertiesForKeys: [.isSymbolicLinkKey], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else { throw Failure.invalidPath }
            for case let child as URL in contents {
                if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    throw Failure.symbolicLink
                }
            }
            if let enumerationError { throw enumerationError }
            try FileManager.default.copyItem(at: from, to: to)
        }
        #if canImport(Darwin)
        var error: NSError?
        var result: Result<Void, Error>?
        NSFileCoordinator().coordinate(readingItemAt: original.root, options: [],
            writingItemAt: target, options: [], error: &error) { from, to in
            result = Result { try copy(from, to) }
        }
        if let error { throw error }
        guard let result else { throw Failure.invalidPath }
        try result.get()
        #else
        try copy(original.root, target)
        #endif
        return relative
    }

    private func coordinateRead<Value>(_ file: URL, operation: (URL) throws -> Value) throws -> Value {
        #if canImport(Darwin)
        var error: NSError?
        var result: Result<Value, Error>?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { target in
            result = Result { try operation(target) }
        }
        if let error { throw error }
        guard let result else { throw Failure.invalidPath }
        return try result.get()
        #else
        return try operation(file)
        #endif
    }

    private func coordinateWrite<Value>(_ file: URL, operation: (URL) throws -> Value) throws -> Value {
        #if canImport(Darwin)
        var error: NSError?
        var result: Result<Value, Error>?
        NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: &error) { target in
            result = Result { try operation(target) }
        }
        if let error { throw error }
        guard let result else { throw Failure.invalidPath }
        return try result.get()
        #else
        return try operation(file)
        #endif
    }
}
