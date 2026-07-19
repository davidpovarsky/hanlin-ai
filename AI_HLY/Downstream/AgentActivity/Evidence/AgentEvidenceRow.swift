import SwiftUI
import UIKit

struct AgentEvidenceRow: View {
    let item: AgentEvidenceItem

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let metadataText {
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let snippet = item.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 16) {
                    if let url = item.primaryURL {
                        Button(openTitle) { openURL(url) }
                    }
                    if let copyValue {
                        Button(copyTitle) { UIPasteboard.general.string = copyValue }
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private var metadataText: String? {
        item.subtitle ?? item.reference ?? item.url.flatMap(URL.init(string:))?.host()
    }

    private var copyValue: String? {
        if item.kind == .sefariaSource { return item.reference ?? item.title }
        return item.url ?? item.deepLink ?? item.reference
    }

    private var openTitle: String {
        switch item.kind {
        case .wikipediaArticle: String(localized: "Open in Wikipedia")
        case .sefariaSource: String(localized: "Open in Sefaria")
        case .githubRepository, .githubFile, .githubCommit: String(localized: "Open in GitHub")
        default: String(localized: "Open")
        }
    }

    private var copyTitle: String {
        item.kind == .sefariaSource
            ? String(localized: "Copy reference")
            : String(localized: "Copy link")
    }

    private var iconName: String {
        switch item.kind {
        case .webPage: "globe"
        case .wikipediaArticle: "character.book.closed"
        case .sefariaSource: "books.vertical"
        case .githubRepository, .githubFile, .githubCommit: "chevron.left.forwardslash.chevron.right"
        case .document, .file: "doc.text"
        case .reminder: "checklist"
        case .calendarEvent: "calendar"
        case .email: "envelope"
        case .contact: "person.crop.circle"
        case .genericItem: "square.stack.3d.up"
        }
    }
}
