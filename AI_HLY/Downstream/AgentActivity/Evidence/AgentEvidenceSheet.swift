import SwiftUI

struct AgentEvidenceSheet: View {
    let items: [AgentEvidenceItem]

    @Environment(\.dismiss) private var dismiss

    private var groups: [AgentEvidenceGroup] {
        let visible = items.filter(\.wasReturnedToModel)
        return EvidenceSection.all.compactMap { section in
            let values = visible.filter { section.kinds.contains($0.kind) }
            return values.isEmpty ? nil : AgentEvidenceGroup(
                id: section.id,
                title: section.title,
                items: values
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if groups.isEmpty {
                        ContentUnavailableView(
                            String(localized: "No sources available"),
                            systemImage: "doc.text.magnifyingglass"
                        )
                    } else {
                        ForEach(groups) { group in
                            Section {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                        AgentEvidenceRow(item: item)
                                        if index < group.items.count - 1 {
                                            Divider().padding(.leading, 44)
                                        }
                                    }
                                }
                            } header: {
                                Text(group.title)
                                    .font(.headline)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(String(localized: "Sources and items"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(String(localized: "Close"), systemImage: "xmark")
                    }
                }
            }
        }
        .onAppear { AgentEvidenceUITrace.sheetOpened(count: items.count) }
    }
}

private struct EvidenceSection {
    var id: String
    var title: String
    var kinds: Set<AgentEvidenceKind>

    static var all: [EvidenceSection] {
        [
            EvidenceSection(id: "web", title: String(localized: "Web sources"), kinds: [.webPage]),
            EvidenceSection(id: "wikipedia", title: String(localized: "Wikipedia"), kinds: [.wikipediaArticle]),
            EvidenceSection(id: "sefaria", title: String(localized: "Sefaria"), kinds: [.sefariaSource]),
            EvidenceSection(id: "github", title: String(localized: "GitHub"), kinds: [.githubRepository, .githubFile, .githubCommit]),
            EvidenceSection(id: "documents", title: String(localized: "Documents"), kinds: [.document, .file]),
            EvidenceSection(id: "reminders", title: String(localized: "Reminders used"), kinds: [.reminder]),
            EvidenceSection(id: "calendar", title: String(localized: "Calendar items"), kinds: [.calendarEvent]),
            EvidenceSection(id: "emails", title: String(localized: "Emails"), kinds: [.email]),
            EvidenceSection(id: "contacts", title: String(localized: "Contacts"), kinds: [.contact]),
            EvidenceSection(id: "other", title: String(localized: "Other items"), kinds: [.databaseRecord, .genericItem])
        ]
    }
}
