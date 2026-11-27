import Foundation
import HanlinPlatformContracts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MiniAppsDeveloperStudio: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Projects") {
                    NavigationLink {
                        MiniAppsStudioLibrary(isCloud: false)
                    } label: { Label("On this device", systemImage: "iphone") }
                    NavigationLink {
                        MiniAppsStudioLibrary(isCloud: true)
                    } label: { Label("iCloud Drive", systemImage: "icloud") }
                }
                Section("Tools") {
                    NavigationLink {
                        MiniAppsStudioLogs()
                    } label: { Label("Live logs", systemImage: "terminal") }
                    NavigationLink {
                        MiniAppsStudioRecoveredDrafts()
                    } label: { Label("Recovered drafts", systemImage: "doc.badge.clock") }
                    Link(destination: URL(string: "https://docs.expo.dev/")!) {
                        Label("Expo reference", systemImage: "book")
                    }
                    Link(destination: URL(string: "https://docs.nativescript.org/")!) {
                        Label("NativeScript reference", systemImage: "book")
                    }
                }
            }
            .navigationTitle("Developer Studio")
            .accessibilityIdentifier("miniapps-studio")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct MiniAppsStudioLibrary: View {
    let isCloud: Bool
    @State private var load = MiniAppsStudioLibraryLoadState()

    var body: some View {
        Group {
            if let workspace = load.workspace {
                MiniAppsStudioBrowser(workspace: workspace, directory: "", title: isCloud ? "iCloud Projects" : "My Projects")
            } else if let error = load.error {
                ContentUnavailableView("Library unavailable", systemImage: "folder.badge.questionmark",
                    description: Text(error))
            } else {
                ProgressView("Opening projects…")
            }
        }
        .task(id: isCloud) {
            // Keep an already opened workspace and its editor/navigation state.
            guard let request = load.begin() else { return }
            let requestedCloud = isCloud
            do {
                let workspace = try await MiniAppsStudioLibraryLoadState.resolveWorkspace {
                    if requestedCloud {
                        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.itorah.chavrusachat") else {
                            throw NSError(domain: "MiniApps.Studio", code: 1,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "iCloud document storage is unavailable for this app on this device. Check iCloud Drive, then reopen this library."])
                        }
                        return container.appending(path: "Documents/MiniAppsStudio", directoryHint: .isDirectory)
                    }
                    return try RuntimeFileLayout.default.workspace(client: .tools, identifier: "miniapp-studio")
                }
                load.succeed(workspace, for: request)
            } catch is CancellationError {
                load.cancel(request)
            } catch {
                guard !Task.isCancelled else {
                    load.cancel(request)
                    return
                }
                load.fail(error.localizedDescription, for: request)
            }
        }
        .onDisappear { load.cancelCurrentRequest() }
    }
}

private struct MiniAppsStudioBrowser: View {
    let workspace: MiniAppsDeveloperWorkspace
    let directory: String
    let title: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [MiniAppsDeveloperWorkspace.Entry] = []
    @State private var showsGallery = false
    @State private var showsImport = false
    @State private var showsPathPrompt = false
    @State private var pathText = ""
    @State private var moving: MiniAppsDeveloperWorkspace.Entry?
    @State private var styling: MiniAppsDeveloperWorkspace.Entry?
    @State private var error: String?

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "folder",
                    description: Text("Choose an example from the gallery or import a source project."))
            }
            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        if isProject(entry) {
                            MiniAppsStudioProjectLoader(url: workspace.root.appending(path: entry.path))
                        } else {
                            MiniAppsStudioBrowser(workspace: workspace, directory: entry.path, title: entry.name)
                        }
                    } label: {
                        let defaultSymbol = isProject(entry) ? "curlybraces.square" : "folder"
                        let style = (try? workspace.style(for: entry.path, defaultSymbol: defaultSymbol))
                            ?? .init(symbol: defaultSymbol)
                        Label(entry.name, systemImage: style.symbol)
                            .foregroundStyle(studioColor(style.color))
                    }
                    .contextMenu {
                        Button("Rename or move", systemImage: "folder.badge.arrow.forward") {
                            moving = entry; pathText = entry.path; showsPathPrompt = true
                        }
                        Button("Icon and color", systemImage: "paintpalette") { styling = entry }
                    }
                } else {
                    Label(entry.name, systemImage: "doc")
                        .contextMenu {
                            Button("Rename or move") {
                                moving = entry; pathText = entry.path; showsPathPrompt = true
                            }
                        }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Gallery", systemImage: "square.grid.2x2") { showsGallery = true }
                    Button("Import source folder", systemImage: "square.and.arrow.down") { showsImport = true }
                    Button("New folder", systemImage: "folder.badge.plus") {
                        moving = nil
                        pathText = directory.isEmpty ? "New Folder" : directory + "/New Folder"
                        showsPathPrompt = true
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Create or import project")
                .accessibilityIdentifier("miniapps-studio-add")
            }
        }
        .task { refresh() }
        .onChange(of: scenePhase) { _, value in if value == .active { refresh() } }
        .refreshable { refresh() }
        .sheet(isPresented: $showsGallery, onDismiss: refresh) {
            NavigationStack { MiniAppsStudioGallery(workspace: workspace, directory: directory) }
        }
        .sheet(item: $styling, onDismiss: refresh) { entry in
            MiniAppsFolderStyleSheet(workspace: workspace, entry: entry,
                defaultSymbol: isProject(entry) ? "curlybraces.square" : "folder")
        }
        .fileImporter(isPresented: $showsImport, allowedContentTypes: [.folder]) { result in
            do {
                let source = try result.get()
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                _ = try workspace.copyProject(from: source,
                    named: source.lastPathComponent + "-" + UUID().uuidString.prefix(8), into: directory)
                refresh()
            } catch { self.error = error.localizedDescription }
        }
        .alert(moving == nil ? "New folder" : "Rename or move", isPresented: $showsPathPrompt) {
            TextField("Path in this library", text: $pathText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Save") {
                do {
                    if let moving { try workspace.move(moving.path, to: pathText) }
                    else { try workspace.createFolder(pathText) }
                    refresh()
                } catch { self.error = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Use / to place an item inside a folder. Existing files are kept.") }
        .alert("Project unavailable", isPresented: errorBinding) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    }
    private func isProject(_ entry: MiniAppsDeveloperWorkspace.Entry) -> Bool {
        FileManager.default.fileExists(atPath: workspace.root.appending(path: entry.path)
            .appending(path: "hanlin.authoring.json").path)
    }
    private func refresh() {
        do { entries = try workspace.entries(in: directory) }
        catch { self.error = error.localizedDescription }
    }
}

private struct MiniAppsStudioGallery: View {
    let workspace: MiniAppsDeveloperWorkspace
    let directory: String
    @Environment(\.dismiss) private var dismiss
    @State private var sdk: MiniAppsStudioSDK?
    @State private var error: String?
    @State private var imported: String?

    var body: some View {
        List {
            if let sdk {
                ForEach(sdk.examples) { example in
                    Button {
                        do {
                            let source = try MiniAppsDeveloperWorkspace(root: URL(fileURLWithPath: sdk.sdkRoot))
                                .url(for: example.path)
                            imported = try workspace.copyProject(from: source,
                                named: example.id + "-" + UUID().uuidString.prefix(8), into: directory)
                        } catch { self.error = error.localizedDescription }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(example.title).font(.headline)
                            Text(example.engine).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("miniapps-gallery-" + example.id)
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ProgressView("Loading examples…")
            }
        }
        .navigationTitle("Example Gallery")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            do { sdk = try await MiniAppsStudioSDK.load() }
            catch { self.error = error.localizedDescription }
        }
        .alert("Project copied", isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } })) {
            Button("Open library") { dismiss() }
        } message: {
            Text("Your independent copy is ready to edit, validate and install.")
        }
    }
}

private struct MiniAppsFolderStyleSheet: View {
    let workspace: MiniAppsDeveloperWorkspace
    let entry: MiniAppsDeveloperWorkspace.Entry
    let defaultSymbol: String
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = "folder"
    @State private var color = "blue"
    @State private var error: String?
    private let symbols = ["folder", "star.fill", "heart.fill", "book.fill", "briefcase.fill", "hammer.fill", "leaf.fill", "bolt.fill"]
    private let colors = ["blue", "green", "orange", "red", "purple", "pink", "yellow", "gray"]

    var body: some View {
        NavigationStack {
            Form {
                Section("SF Symbol") {
                    TextField("Symbol name", text: $symbol).textInputAutocapitalization(.never).autocorrectionDisabled()
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(symbols, id: \.self) { value in
                                Button { symbol = value } label: { Image(systemName: value).padding(10) }
                            }
                        }
                    }
                    Label(entry.name, systemImage: symbol).foregroundStyle(studioColor(color))
                }
                Picker("Color", selection: $color) {
                    ForEach(colors, id: \.self) { Text($0.capitalized).tag($0) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Folder appearance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try workspace.setStyle(.init(symbol: symbol, color: color), for: entry.path)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(UIImage(systemName: symbol) == nil)
                }
            }
            .task {
                do {
                    let value = try workspace.style(for: entry.path, defaultSymbol: defaultSymbol)
                    symbol = value.symbol; color = value.color
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

private func studioColor(_ name: String) -> Color {
    switch name {
    case "green": .green
    case "orange": .orange
    case "red": .red
    case "purple": .purple
    case "pink": .pink
    case "yellow": .yellow
    case "gray": .gray
    default: .blue
    }
}

struct MiniAppsStudioProjectLoader: View {
    let url: URL
    var recoveredDraft: MiniAppsStudioDraft?
    @State private var project: MiniAppsStudioProject?
    @State private var error: String?

    var body: some View {
        Group {
            if let project { MiniAppsStudioProjectView(project: project) }
            else if let error {
                ContentUnavailableView("Project unavailable", systemImage: "doc.badge.exclamationmark", description: Text(error))
            } else { ProgressView("Opening source…") }
        }
        .task {
            do {
                let model = try MiniAppsStudioProject(project: url)
                if let recoveredDraft { try model.recover(recoveredDraft) }
                project = model
            } catch { self.error = error.localizedDescription }
        }
    }
}

private enum MiniAppsEditorTheme: String, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

private struct MiniAppsStudioProjectView: View {
    @Bindable var project: MiniAppsStudioProject
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("miniapps.studio.fontName") private var fontName = "Menlo-Regular"
    @AppStorage("miniapps.studio.fontSize") private var fontSize = 15.0
    @AppStorage("miniapps.studio.theme") private var theme = MiniAppsEditorTheme.system.rawValue
    @State private var caret = CGRect.zero
    @State private var showsFontPicker = false
    @State private var showsImport = false
    @State private var showsPathPrompt = false
    @State private var newPath = ""
    @State private var movingPath: String?
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(project.files) { entry in
                        Button(entry.path) { perform { try project.select(entry.path) } }
                    }
                } label: {
                    Label(project.selectedPath ?? "Source files", systemImage: "doc.text")
                        .lineLimit(1).truncationMode(.middle)
                }
                .accessibilityIdentifier("miniapps-studio-files")
                .disabled(project.isBusy)
                Spacer()
                if project.isDirty { Image(systemName: "circle.fill").font(.system(size: 6)).accessibilityLabel("Unsaved changes") }
                if project.isBusy { ProgressView() }
            }.padding(10)
            if project.conflict {
                VStack(alignment: .leading) {
                    Text("This file changed elsewhere. Your draft is preserved.").font(.callout)
                    HStack {
                        Button("Reload file") { perform { try project.reloadAfterConflict() } }
                        Button("Save a copy") { perform { try project.saveConflictCopy() } }
                    }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.15))
            }
            GeometryReader { geometry in
                MiniAppsCodeTextView(text: Binding(get: { project.text }, set: {
                    project.text = $0
                    project.edited()
                }), selection: $project.selection, fontName: fontName, fontSize: fontSize, caret: $caret)
                    .accessibilityIdentifier("miniapps-studio-editor")
                    .disabled(project.isBusy)
                    .overlay(alignment: .topLeading) {
                        if project.showsSuggestions, let inspection = project.inspection,
                           inspection.version == project.version, !inspection.completions.isEmpty {
                            completionList(inspection)
                                .frame(width: min(320, max(100, geometry.size.width - 16)), height: min(150, geometry.size.height / 2))
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 3)
                                .offset(x: min(max(8, caret.minX), max(8, geometry.size.width - 328)),
                                        y: min(max(8, caret.maxY + 4), max(8, geometry.size.height - 160)))
                        }
                    }
            }
            if let inspection = project.inspection,
               !inspection.display.isEmpty || !inspection.signature.isEmpty || !inspection.documentation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inspection.signature.isEmpty ? inspection.display : inspection.signature)
                        .font(.caption.monospaced()).textSelection(.enabled)
                    if !inspection.documentation.isEmpty {
                        Text(inspection.documentation).font(.caption).lineLimit(4).textSelection(.enabled)
                    }
                    Link("Open API reference", destination: inspection.documentationURL).font(.caption)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial)
            }
            HStack {
                if let report = project.report {
                    Button(report.succeeded ? "Validation succeeded" : "\(report.diagnostics.count) diagnostics") { showsDiagnostics = true }
                } else if let count = project.inspection?.diagnostics.count, count > 0 {
                    Button("\(count) diagnostics") { showsDiagnostics = true }
                } else if let helpError = project.helpError {
                    Text(helpError).lineLimit(2)
                }
                Spacer()
                Text("Ln \(lineNumber), \(project.engine)").foregroundStyle(.secondary)
            }.font(.caption).padding(8)
        }
        .navigationTitle(project.workspace.root.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(MiniAppsEditorTheme(rawValue: theme)?.colorScheme)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await project.validate() } } label: { Image(systemName: "checkmark.circle") }
                    .accessibilityLabel("Validate source").disabled(project.isBusy)
                    .accessibilityIdentifier("miniapps-studio-validate")
                Button {
                    Task {
                        if let archive = await project.build() {
                            await HanlinScriptingPlatform.shared.importPackage(from: archive)
                            showsImport = true
                        }
                    }
                } label: { Image(systemName: "play.fill") }
                    .accessibilityLabel("Build and install").disabled(project.isBusy)
                    .accessibilityIdentifier("miniapps-studio-build-install")
                Menu {
                    Button("Save", systemImage: "square.and.arrow.down") { perform { try project.save() } }
                        .disabled(project.isBusy)
                    Button("New source file", systemImage: "doc.badge.plus") { movingPath = nil; newPath = "new.ts"; showsPathPrompt = true }
                        .disabled(project.isBusy)
                    Button("Rename or move file", systemImage: "folder.badge.arrow.forward") {
                        movingPath = project.selectedPath; newPath = project.selectedPath ?? ""; showsPathPrompt = true
                    }.disabled(project.isBusy)
                    Button("Choose font", systemImage: "textformat") { showsFontPicker = true }
                    Menu("Font size") {
                        ForEach([12.0, 15.0, 18.0, 22.0], id: \.self) { size in
                            Button("\(Int(size)) pt") { fontSize = size }
                        }
                    }
                    Picker("Theme", selection: $theme) {
                        ForEach(MiniAppsEditorTheme.allCases, id: \.rawValue) { value in
                            Text(value.rawValue.capitalized).tag(value.rawValue)
                        }
                    }
                    Button("Show suggestions", systemImage: "text.cursor") { project.showsSuggestions = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Editor options")
                .accessibilityIdentifier("miniapps-studio-editor-options")
            }
        }
        .task(id: "\(project.version):\(project.selection.location):\(project.selectedCompletion ?? "")") {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await project.inspect()
        }
        .task(id: project.version) {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            if !project.conflict && !project.isBusy { perform { try project.save() } }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { perform { try project.save() } } }
        .onDisappear { perform { try project.save() } }
        .sheet(isPresented: $showsFontPicker) { MiniAppsStudioFontPicker(fontName: $fontName) }
        .sheet(isPresented: $showsImport) {
            NavigationStack { ScriptingPackageImportView(platform: .shared) }
        }
        .sheet(isPresented: $showsDiagnostics) { diagnostics }
        .alert(movingPath == nil ? "New source file" : "Rename or move", isPresented: $showsPathPrompt) {
            TextField("Relative path", text: $newPath).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Save") {
                perform {
                    if movingPath != nil {
                        try project.moveSelectedFile(to: newPath)
                    } else {
                        try project.save()
                        try project.workspace.createFile(newPath)
                        try project.refreshFiles()
                        try project.select(newPath)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Editor", isPresented: Binding(get: { project.error != nil }, set: { if !$0 { project.error = nil } })) {
            Button("OK") { project.error = nil }
        } message: { Text(project.error ?? "") }
    }

    private var lineNumber: Int {
        let prefix = (project.text as NSString).substring(to: min(project.selection.location, project.text.utf16.count))
        return prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { project.error = error.localizedDescription }
    }

    private func completionList(_ inspection: MiniAppsEditorInspection) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(inspection.completions) { completion in
                    HStack {
                        Button(completion.name) { project.apply(completion) }.font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { project.selectedCompletion = completion.name } label: { Image(systemName: "info.circle") }
                            .accessibilityLabel("Documentation for " + completion.name)
                    }.padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
        }
    }

    private var diagnostics: some View {
        NavigationStack {
            List(project.report?.diagnostics ?? project.inspection?.diagnostics ?? []) { diagnostic in
                VStack(alignment: .leading, spacing: 5) {
                    Text(diagnostic.message)
                    Text([diagnostic.file, diagnostic.line.map { "line \($0)" }, diagnostic.code]
                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Diagnostics")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsDiagnostics = false } } }
        }
    }
}

private struct MiniAppsCodeTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Environment(\.isEnabled) private var isEnabled
    let fontName: String
    let fontSize: Double
    @Binding var caret: CGRect

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.isFindInteractionEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 20, right: 8)
        view.backgroundColor = .secondarySystemGroupedBackground
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEnabled
        if view.text != text { view.text = text }
        view.font = UIFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if view.selectedRange != selection, NSMaxRange(selection) <= (view.text as NSString).length { view.selectedRange = selection }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MiniAppsCodeTextView
        init(_ parent: MiniAppsCodeTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateSelection(textView)
        }
        func textViewDidChangeSelection(_ textView: UITextView) { updateSelection(textView) }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if let text = scrollView as? UITextView { updateCaret(text) }
        }
        private func updateSelection(_ view: UITextView) {
            parent.selection = view.selectedRange
            updateCaret(view)
        }
        private func updateCaret(_ view: UITextView) {
            guard let range = view.selectedTextRange else { return }
            parent.caret = view.caretRect(for: range.end).offsetBy(dx: -view.contentOffset.x, dy: -view.contentOffset.y)
        }
    }
}

private struct MiniAppsStudioFontPicker: UIViewControllerRepresentable {
    @Binding var fontName: String
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = true
        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIFontPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        let parent: MiniAppsStudioFontPicker
        init(_ parent: MiniAppsStudioFontPicker) { self.parent = parent }
        func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            if let descriptor = viewController.selectedFontDescriptor { parent.fontName = UIFont(descriptor: descriptor, size: 15).fontName }
            parent.dismiss()
        }
        func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) { parent.dismiss() }
    }
}

private enum MiniAppsStudioLogReader {
    struct Snapshot: Sendable {
        let files: [URL]
        let selected: URL?
        let text: String
        let isTail: Bool
    }

    nonisolated static func read(root: URL, selectedName: String?) throws -> Snapshot {
        let files = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            .filter {
                let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values.isRegularFile == true && values.isSymbolicLink != true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let selected = files.first(where: { $0.lastPathComponent == selectedName }) ?? files.last else {
            return Snapshot(files: [], selected: nil, text: "", isTail: false)
        }
        let handle = try FileHandle(forReadingFrom: selected)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let limit: UInt64 = 512 * 1_024
        let start = size > limit ? size - limit : 0
        try handle.seek(toOffset: start)
        let bytes = try handle.read(upToCount: Int(limit)) ?? Data()
        var text = String(decoding: bytes, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return Snapshot(files: files, selected: selected, text: text, isTail: start > 0)
    }
}

private struct MiniAppsStudioLogs: View {
    @State private var output = ""
    @State private var search = ""
    @State private var files: [URL] = []
    @State private var selectedName: String?
    @State private var selectedFile: URL?
    @State private var isTail = false
    private var visible: String {
        search.isEmpty ? output : output.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedStandardContains(search) }.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            if isTail {
                Text("Showing and searching the most recent 512 KB. Export the file to read the complete log.")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            ScrollView {
                Text(visible.isEmpty ? "No matching log messages" : visible)
                    .font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).padding()
            }
        }
        .navigationTitle("Live logs")
        .searchable(text: $search, prompt: "Find messages")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(files, id: \.path) { file in
                        Button(file.lastPathComponent) { selectedName = file.lastPathComponent }
                    }
                } label: { Label(selectedName ?? "Choose log", systemImage: "doc.text") }
                if let selectedFile {
                    ShareLink(item: selectedFile) { Label("Export complete log", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .task(id: selectedName) {
            let root = RuntimeFileLayout.default.logs
            while !Task.isCancelled {
                let requested = selectedName
                do {
                    let snapshot = try await Task.detached(priority: .utility) {
                        try MiniAppsStudioLogReader.read(root: root, selectedName: requested)
                    }.value
                    guard !Task.isCancelled else { return }
                    files = snapshot.files
                    selectedFile = snapshot.selected
                    output = snapshot.text
                    isTail = snapshot.isTail
                } catch {
                    guard !Task.isCancelled else { return }
                    output = error.localizedDescription
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
}
