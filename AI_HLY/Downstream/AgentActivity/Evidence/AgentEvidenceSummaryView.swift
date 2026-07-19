import SwiftUI

struct AgentEvidenceSummaryView: View {
    let items: [AgentEvidenceItem]
    let onOpen: () -> Void

    private var visibleItems: [AgentEvidenceItem] {
        items.filter(\.wasReturnedToModel)
    }

    var body: some View {
        if !visibleItems.isEmpty {
            Button {
                AgentEvidenceUITrace.summaryPresented(count: visibleItems.count)
                onOpen()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: summaryIcon)
                        .font(.caption)
                    Text(summaryTitle)
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryTitle)
            .accessibilityValue(String(visibleItems.count))
            .accessibilityHint(String(localized: "Open sources and items"))
        }
    }

    private var summaryTitle: String {
        let count = visibleItems.count
        if visibleItems.allSatisfy({ $0.kind == .sefariaSource }) {
            return count == 1
                ? String(localized: "1 Torah source")
                : String(format: String(localized: "%lld Torah sources"), count)
        }
        if visibleItems.allSatisfy({ $0.kind == .reminder }) {
            return count == 1
                ? String(localized: "1 Reminder used")
                : String(format: String(localized: "%lld Reminders used"), count)
        }
        if visibleItems.allSatisfy({ $0.kind.isSourceLike }) {
            return count == 1
                ? String(localized: "1 Source")
                : String(format: String(localized: "%lld Sources"), count)
        }
        return String(format: String(localized: "%lld Sources and items"), count)
    }

    private var summaryIcon: String {
        if visibleItems.allSatisfy({ $0.kind == .sefariaSource }) { return "books.vertical" }
        if visibleItems.allSatisfy({ $0.kind == .reminder }) { return "checklist" }
        if visibleItems.allSatisfy({ $0.kind.isSourceLike }) { return "globe" }
        return "square.stack.3d.up"
    }
}

extension AgentEvidenceKind {
    var isSourceLike: Bool {
        switch self {
        case .webPage, .wikipediaArticle, .sefariaSource, .githubRepository,
             .githubFile, .githubCommit, .document, .file, .databaseRecord:
            return true
        case .reminder, .calendarEvent, .email, .contact, .genericItem:
            return false
        }
    }
}

enum AgentEvidenceUITrace {
    static func summaryPresented(count: Int) {
        log("evidenceSummaryPresented", ["count": count])
    }

    static func sheetOpened(count: Int) {
        log("evidenceSheetOpened", ["count": count])
    }

    static func itemOpened(_ item: AgentEvidenceItem) {
        log("evidenceItemOpened", ["kind": item.kind.rawValue])
    }

    private static func log(_ event: String, _ fields: [String: Any]) {
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        NativeToolTraceLogger.shared.log(event, fields)
    }
}
