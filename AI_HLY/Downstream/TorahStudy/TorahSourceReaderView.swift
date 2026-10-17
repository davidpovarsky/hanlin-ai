import Foundation
import SwiftUI
import TorahLibraryKit

/// In-app reader for primary Torah study sources.
/// Displays authoritative source text, preceding/following context, and visual highlighting of matched excerpts.
public struct TorahSourceReaderView: View {
    public let deepLink: TorahStudyDeepLink
    @Environment(\.dismiss) private var dismiss
    @State private var source: StudySource? = nil
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    public init(deepLink: TorahStudyDeepLink) {
        self.deepLink = deepLink
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(String(localized: "טוען מקור..."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView(
                        String(localized: "שגיאה בטעינת המקור"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let studySource = source {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerSection(studySource: studySource)
                            Divider()

                            if let before = studySource.contextBefore, !before.isEmpty {
                                Text(before)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }

                            highlightedText(primary: studySource.primaryText, highlight: deepLink.highlightText)
                                .font(.title3)
                                .lineSpacing(6)
                                .environment(\.layoutDirection, .rightToLeft)

                            if let after = studySource.contextAfter, !after.isEmpty {
                                Text(after)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }

                            if !studySource.links.isEmpty {
                                linksSection(links: studySource.links)
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "מקור לא נמצא"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(String(localized: "לא נמצא תוכן עבור המזהה המבוקש."))
                    )
                }
            }
            .navigationTitle(deepLink.workTitle ?? deepLink.locator.workKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "סגור")) {
                        TorahStudyNavigationRouter.shared.closeReader()
                        dismiss()
                    }
                }
            }
            .task {
                await loadSource()
            }
        }
    }

    private func headerSection(studySource: StudySource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deepLink.workTitle ?? studySource.locator.workKey)
                .font(.headline)
            Text(studySource.locator.positionValue)
                .font(.subheadline)
                .foregroundColor(.secondary)

            let version = studySource.versionMetadata.versionTitle
            if !version.isEmpty {
                Text(version)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func highlightedText(primary: String, highlight: String?) -> Text {
        guard let highlight, !highlight.isEmpty else {
            return Text(primary)
        }

        let cleanHighlight = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = primary.range(of: cleanHighlight, options: .caseInsensitive) {
            let before = String(primary[..<range.lowerBound])
            let match = String(primary[range])
            let after = String(primary[range.upperBound...])

            return Text(before) + Text(match).bold().foregroundColor(.accentColor) + Text(after)
        }

        // Token-based fallback highlight if exact match not found
        let tokens = cleanHighlight.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 3 }
        if let firstToken = tokens.first, let range = primary.range(of: firstToken, options: .caseInsensitive) {
            let before = String(primary[..<range.lowerBound])
            let match = String(primary[range])
            let after = String(primary[range.upperBound...])
            return Text(before) + Text(match).bold().foregroundColor(.accentColor) + Text(after)
        }

        return Text(primary)
    }

    private func linksSection(links: [TorahLinkedSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "פירושים וקישורים"))
                .font(.headline)
            ForEach(links) { link in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(link.type)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        Text(link.sourceTitle)
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Text(link.category)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if !link.primaryText.isEmpty {
                        Text(link.primaryText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 12)
    }

    private func loadSource() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await TorahLibraryCoordinator.shared.getSection(locator: deepLink.locator)
            await MainActor.run {
                self.source = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
