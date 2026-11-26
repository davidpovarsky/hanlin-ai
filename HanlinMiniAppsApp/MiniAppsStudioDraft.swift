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

    @MainActor static func all() throws -> [Self] {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(Self.self, from: Data(contentsOf: $0))
        }.sorted { $0.savedAt > $1.savedAt }
    }
}

struct MiniAppsStudioRecoveredDrafts: View {
    @State private var drafts: [MiniAppsStudioDraft] = []
    @State private var error: String?

    var body: some View {
        List {
            if drafts.isEmpty {
                ContentUnavailableView("No recovered drafts", systemImage: "checkmark.circle",
                    description: Text(error ?? "Your source changes have been saved."))
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
        }
        .navigationTitle("Recovered drafts")
        .task {
            do { drafts = try MiniAppsStudioDraft.all() }
            catch { self.error = error.localizedDescription }
        }
    }
}
