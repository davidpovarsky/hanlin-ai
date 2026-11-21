import SwiftData
import SwiftUI

/// This small view is the only observer that persists draft keystrokes. Keeping
/// its dependency below ChatView prevents each edit rebuilding the transcript,
/// publishing a new compact endpoint and invalidating the history query.
@MainActor
struct HanlinDraftPersistence: View {
    let draft: HanlinComposerDraft
    let record: ChatRecords
    let temporary: Bool
    @Environment(\.modelContext) private var context

    private struct SaveKey: Equatable {
        let revision: UUID
        let conversationID: UUID?
        let temporary: Bool
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: SaveKey(revision: draft.snapshot.revision,
                              conversationID: record.id, temporary: temporary)) {
                guard !temporary else { return }
                let snapshot = draft.snapshot
                let conversationID = record.id
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
                guard !Task.isCancelled,
                      record.modelContext === context,
                      record.id == conversationID,
                      draft.snapshot.revision == snapshot.revision,
                      record.input != snapshot.text else { return }
                record.input = snapshot.text
                do { try context.save() }
                catch { print("Failed to save chat draft: \(error)") }
            }
    }
}
