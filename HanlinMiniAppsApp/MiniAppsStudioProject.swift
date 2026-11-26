import Foundation
import HanlinPlatformContracts
import Observation

struct MiniAppsEditorInspection: Decodable, Sendable {
    struct Completion: Decodable, Identifiable, Sendable {
        let name: String
        let kind: String
        let insertText: String
        let replacementStart: Int?
        let replacementLength: Int?
        var id: String { name }
    }
    let version: Int
    let file: String
    let compilerVersion: String
    let completions: [Completion]
    let display: String
    let documentation: String
    let signature: String
    let argumentIndex: Int?
    let diagnostics: [HanlinMiniAppAuthoringDiagnostic]
    let documentationURL: URL
}

struct MiniAppsStudioSDK: Decodable, Sendable {
    struct Example: Decodable, Identifiable, Sendable {
        let id: String
        let engine: String
        let title: String
        let path: String
        let entry: String
    }
    struct Engine: Decodable, Sendable { let examples: [Example]? }
    let sdkRoot: String
    let engines: [String: Engine]
    var examples: [Example] {
        engines.values.flatMap { $0.examples ?? [] }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func load() async throws -> Self {
        let result = try await MiniAppAuthoringService.sdk()
        return try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(result))
    }
}

@MainActor @Observable
final class MiniAppsStudioProject {
    struct Authoring: Decodable {
        let engine: String
        let entry: String
        let sourceRoot: String?
    }

    let workspace: MiniAppsDeveloperWorkspace
    let engine: String
    private var draftID = UUID()
    private(set) var files: [MiniAppsDeveloperWorkspace.Entry] = []
    private(set) var document: MiniAppsDeveloperWorkspace.Document?
    var text = ""
    var selection = NSRange(location: 0, length: 0)
    private(set) var version = 0
    private(set) var inspection: MiniAppsEditorInspection?
    private(set) var report: HanlinMiniAppAuthoringReport?
    private(set) var isBusy = false
    private(set) var helpError: String?
    var error: String?
    private(set) var conflict = false
    var selectedCompletion: String?
    var showsSuggestions = true
    var isDirty: Bool { document.map { text != $0.text } ?? false }
    var selectedPath: String? { document?.path }

    init(project: URL) throws {
        guard try project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw MiniAppsDeveloperWorkspace.Failure.invalidPath
        }
        let outer = try MiniAppsDeveloperWorkspace(root: project)
        let outerAuthor = try JSONDecoder().decode(Authoring.self,
            from: outer.read("hanlin.authoring.json").original)
        workspace = try outerAuthor.sourceRoot.map {
            try MiniAppsDeveloperWorkspace(root: outer.url(for: $0, allowRoot: true))
        } ?? outer
        let author = try JSONDecoder().decode(Authoring.self,
            from: workspace.read("hanlin.authoring.json").original)
        guard ["expo", "nativescript", "scriptwidget"].contains(author.engine) else {
            throw MiniAppsDeveloperWorkspace.Failure.invalidPath
        }
        engine = author.engine
        files = try workspace.sourceFiles()
        let initial = try workspace.read(author.entry)
        document = initial
        text = initial.text
    }

    func refreshFiles() throws { files = try workspace.sourceFiles() }

    func select(_ path: String) throws {
        try save()
        let next = try workspace.read(path)
        document = next
        text = next.text
        selection = NSRange(location: 0, length: 0)
        version += 1
        inspection = nil
        selectedCompletion = nil
        conflict = false
    }

    func edited() {
        version += 1
        selectedCompletion = nil
        showsSuggestions = true
        report = nil
        guard let document else { return }
        do {
            if isDirty {
                try MiniAppsStudioDraft(id: draftID, projectPath: workspace.root.path, path: document.path,
                    text: text, original: document.original, savedAt: .now).persist()
            } else {
                try MiniAppsStudioDraft.remove(draftID)
            }
        } catch { self.error = "The recovery draft could not be saved: " + error.localizedDescription }
    }

    func recover(_ draft: MiniAppsStudioDraft) throws {
        guard draft.projectPath == workspace.root.path else { throw MiniAppsDeveloperWorkspace.Failure.invalidPath }
        let current = try workspace.read(draft.path)
        document = .init(path: draft.path, text: String(decoding: draft.original, as: UTF8.self), original: draft.original)
        text = draft.text
        draftID = draft.id
        conflict = current.original != draft.original
        selection = NSRange(location: 0, length: 0)
        version += 1
    }

    func save() throws {
        guard let document else { return }
        do {
            if isDirty {
                self.document = try workspace.save(text, document: document)
            } else if try workspace.read(document.path).original != document.original {
                throw MiniAppsDeveloperWorkspace.Failure.changedOnDisk
            }
            try MiniAppsStudioDraft.remove(draftID)
            conflict = false
        } catch MiniAppsDeveloperWorkspace.Failure.changedOnDisk {
            conflict = true
            throw MiniAppsDeveloperWorkspace.Failure.changedOnDisk
        }
    }

    func reloadAfterConflict() throws {
        guard let path = document?.path else { return }
        let current = try workspace.read(path)
        document = current
        text = current.text
        try MiniAppsStudioDraft.remove(draftID)
        conflict = false
        version += 1
    }

    func saveConflictCopy() throws {
        guard let path = document?.path else { return }
        let ext = (path as NSString).pathExtension
        let relativeBase = (path as NSString).deletingPathExtension
        let copied = relativeBase + "-copy-" + UUID().uuidString.prefix(8)
            + (ext.isEmpty ? "" : "." + ext)
        try workspace.createFile(copied, text: text)
        document = try workspace.read(copied)
        try MiniAppsStudioDraft.remove(draftID)
        conflict = false
        try refreshFiles()
        version += 1
    }

    func inspect() async {
        guard let path = document?.path, ["ts", "tsx", "js", "jsx", "mjs", "cts", "mts"].contains(URL(fileURLWithPath: path).pathExtension) else {
            inspection = nil
            return
        }
        let requestedVersion = version
        let source = text
        let position = min(selection.location, source.utf16.count)
        do {
            let result = try await AppRuntimeCore.shared.node.inspectMiniAppSource(
                project: workspace.root, engine: engine, file: path, source: source,
                position: position, version: requestedVersion, completionName: selectedCompletion)
            let value = try JSONDecoder().decode(MiniAppsEditorInspection.self, from: JSONEncoder().encode(result))
            guard !Task.isCancelled, version == requestedVersion, document?.path == path else { return }
            inspection = value
            helpError = nil
        } catch is CancellationError {
        } catch {
            guard version == requestedVersion else { return }
            helpError = error.localizedDescription
        }
    }

    func apply(_ completion: MiniAppsEditorInspection.Completion) {
        guard let inspection, inspection.version == version, inspection.file == document?.path else { return }
        let source = text as NSString
        let position = min(selection.location, source.length)
        let range: NSRange
        if let start = completion.replacementStart, let length = completion.replacementLength,
           start >= 0, length >= 0, start + length <= source.length {
            range = NSRange(location: start, length: length)
        } else {
            let prefix = source.substring(to: position) as NSString
            let expression = try? NSRegularExpression(pattern: #"[$\p{L}\p{N}\p{M}_]+$"#)
            range = expression?.firstMatch(in: prefix as String, range: NSRange(location: 0, length: prefix.length))?.range
                ?? NSRange(location: position, length: 0)
        }
        text = source.replacingCharacters(in: range, with: completion.insertText)
        selection = NSRange(location: range.location + completion.insertText.utf16.count, length: 0)
        edited()
        showsSuggestions = false
    }

    func validate() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try save()
            report = try await MiniAppAuthoringService.validate(project: workspace.root, engine: engine)
        } catch { self.error = error.localizedDescription }
    }

    func build() async -> URL? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            try save()
            let result = try await MiniAppAuthoringService.build(project: workspace.root, engine: engine)
            report = result
            return result.succeeded ? result.archivePath.map { URL(fileURLWithPath: $0) } : nil
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}
