import Foundation
import SwiftUI
import HanlinPresentationKit

/// Read-only projection of the existing AgentRun evidence and transcript.
/// This neither retrieves sources nor owns a parallel source database.
struct HanlinMessageCitations: Sendable {
    let messageID: UUID
    let evidence: [AgentEvidenceItem]
    let segments: [String: String]

    init(messageID: UUID, evidence: [AgentEvidenceItem], transcript: [AgentTranscriptItem]) {
        self.messageID = messageID; self.evidence = evidence
        segments = Dictionary(transcript.compactMap { item -> (String, String)? in
            guard item.kind == .assistantText, let id = item.externalID, let text = item.text else { return nil }
            return (id, text)
        }, uniquingKeysWith: { first, _ in first })
    }

    var sources: [HanlinSourceReference] {
        evidence.filter(\.wasReturnedToModel).map { item in
            let url = item.url.flatMap(URL.init(string:))
            return .init(id: item.id, title: item.title, url: url,
                iconURL: url?.host.flatMap { URL(string: "https://\($0)/favicon.ico") })
        }
    }

    func projection(for text: String) -> HanlinCitationProjection {
        // Trimming only mirrors the original legacy bubble. Ambiguous identical
        // transcript segments are left without inline provenance.
        let matches = segments.filter { $0.value == text || $0.value.trimmingCharacters(in: .whitespacesAndNewlines) == text }
        guard matches.count == 1, let segment = matches.first else {
            return .make(text: text, messageID: messageID, sources: sources, anchors: [])
        }
        let original = segment.value, segmentID = segment.key
        let leading = original == text ? 0 : original.prefix(while: { $0.isWhitespace }).utf16.count
        let originalValue = original as NSString
        let anchors = evidence.flatMap { source -> [HanlinCitationAnchor] in
            (source.claimAnchors ?? []).compactMap { anchor in
                guard anchor.transcriptSegmentID == segmentID,
                      anchor.prefixUTF16Length <= originalValue.length, anchor.prefixUTF16Length >= 0,
                      ChatSavedExcerpt.digest(originalValue.substring(to: anchor.prefixUTF16Length)) == anchor.prefixSHA256,
                      anchor.startUTF16 >= leading, anchor.endUTF16 > anchor.startUTF16,
                      anchor.endUTF16 - leading <= text.utf16.count else { return nil }
                return .init(sourceID: source.id, range: (anchor.startUTF16 - leading)..<(anchor.endUTF16 - leading))
            }
        }
        return .make(text: text, messageID: messageID, sources: sources, anchors: anchors)
    }
}

private struct HanlinMessageCitationsKey: EnvironmentKey {
    static let defaultValue: HanlinMessageCitations? = nil
}
extension EnvironmentValues {
    var hanlinMessageCitations: HanlinMessageCitations? {
        get { self[HanlinMessageCitationsKey.self] }
        set { self[HanlinMessageCitationsKey.self] = newValue }
    }
}
