import Foundation
import SwiftUI
import UIKit

struct MiniAppsStudioDraft: Codable, Identifiable, Sendable {
    let id: UUID
    let projectPath: String
    let path: String
    let text: String
    let original: Data
    let savedAt: Date

    struct RecoveryIssue: Identifiable, Sendable {
        let file: URL
        let message: String
        var id: String { file.path }
    }

    struct RecoveryListing: Sendable {
        let drafts: [MiniAppsStudioDraft]
        let issues: [RecoveryIssue]
    }

    @MainActor private static func directory() throws -> URL {
        try RuntimeFileLayout.default.workspace(client: .tools, identifier: "miniapp-studio-drafts")
    }

    @MainActor func persist() throws {
        let file = try Self.directory().appending(path: id.uuidString + ".json")
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    @MainActor static func remove(_ id: UUID) throws {
        let file = try directory().appending(path: id.uuidString + ".json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    @MainActor static func all() throws -> RecoveryListing {
        try readAll(from: directory())
    }

    static func readAll(from directory: URL) throws -> RecoveryListing {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        var drafts: [Self] = []
        var issues: [RecoveryIssue] = []
        for file in files.filter({ $0.pathExtension == "json" }) {
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw MiniAppsDeveloperWorkspace.Failure.invalidPath
                }
                let draft = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
                guard file.deletingPathExtension().lastPathComponent == draft.id.uuidString else {
                    throw MiniAppsDeveloperWorkspace.Failure.invalidPath
                }
                drafts.append(draft)
            } catch {
                // Keep unreadable bytes for export; one damaged file must not
                // hide another window's valid recovery journal.
                issues.append(.init(file: file, message: error.localizedDescription))
            }
        }
        return RecoveryListing(drafts: drafts.sorted { $0.savedAt > $1.savedAt },
            issues: issues.sorted { $0.file.lastPathComponent < $1.file.lastPathComponent })
    }
}

struct MiniAppsStudioRecoveredDrafts: View {
    @State private var drafts: [MiniAppsStudioDraft] = []
    @State private var issues: [MiniAppsStudioDraft.RecoveryIssue] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                ContentUnavailableView("Recovery unavailable", systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if drafts.isEmpty && issues.isEmpty {
                ContentUnavailableView("No recovered drafts", systemImage: "checkmark.circle",
                    description: Text("Your source changes have been saved."))
            }
            ForEach(drafts) { draft in
                NavigationLink {
                    MiniAppsStudioProjectLoader(url: URL(fileURLWithPath: draft.projectPath), recoveredDraft: draft)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.path)
                        Text(draft.savedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    ShareLink(item: draft.text) { Label("Export draft text", systemImage: "square.and.arrow.up") }
                    Button("Copy draft text", systemImage: "doc.on.doc") { UIPasteboard.general.string = draft.text }
                }
            }
            if !issues.isEmpty {
                Section("Drafts that could not be read") {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(issue.file.lastPathComponent).font(.caption)
                            Text(issue.message).font(.caption).foregroundStyle(.secondary)
                            ShareLink(item: issue.file) {
                                Label("Export original draft file", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recovered drafts")
        .task {
            do {
                let listing = try MiniAppsStudioDraft.all()
                drafts = listing.drafts
                issues = listing.issues
            } catch { self.error = error.localizedDescription }
        }
    }
}
