import Foundation
import SwiftUI
import HanlinPresentationKit

/// Read-only projection of the existing AgentRun evidence and transcript.
/// This neither retrieves sources nor owns a parallel source database.
struct HanlinMessageCitations: Sendable {
    let messageID: UUID
    let evidence: [AgentEvidenceItem]
    let segments: [String: String]

    init(messageID: UUID, evidence: [AgentEvidenceItem], transcript: [AgentTranscriptItem],
         resources: [Resource] = []) {
        self.messageID = messageID
        self.evidence = AgentEvidenceAccumulator(items: evidence + LegacyResourcesEvidenceAdapter.items(
            from: resources, providerName: nil)).items
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

    func projection(for text: String, partID: String? = nil) -> HanlinCitationProjection {
        let references = sources
        // Explicit provider links are durable provenance in the original
        // message itself. They support all providers, including tool-using
        // Chat Completions, without guessing from a message-level source list.
        var anchors = HanlinCitationProjection.explicitSourceLinkAnchors(text: text, sources: references)
        let matches = matchingSegments(for: text)
        var namespace = partID ?? "answer"
        if matches.count == 1, let match = matches.first {
            let originalValue = match.text as NSString
            let leading = match.range.location
            namespace = partID ?? "\(match.id):fragment-\(leading)"
            anchors += evidence.flatMap { source -> [HanlinCitationAnchor] in
                (source.claimAnchors ?? []).compactMap { anchor in
                    guard anchor.transcriptSegmentID == match.id,
                          anchor.prefixUTF16Length <= originalValue.length, anchor.prefixUTF16Length >= 0,
                          ChatSavedExcerpt.digest(originalValue.substring(to: anchor.prefixUTF16Length)) == anchor.prefixSHA256,
                          anchor.startUTF16 >= leading, anchor.endUTF16 > anchor.startUTF16,
                          anchor.endUTF16 <= anchor.prefixUTF16Length,
                          anchor.endUTF16 <= NSMaxRange(match.range) else { return nil }
                    return .init(sourceID: source.id, range: (anchor.startUTF16 - leading)..<(anchor.endUTF16 - leading))
                }
            }
        }
        return .make(text: text, messageID: messageID, sources: references, anchors: anchors, namespace: namespace)
    }

    private func matchingSegments(for text: String) -> [(id: String, text: String, range: NSRange)] {
        guard !text.isEmpty else { return [] }
        // OpenUI and ordered model content split the original answer into
        // Markdown fragments. Map only an exact, unique occurrence, then keep
        // the original hashed prefix and UTF-16 coordinates for validation.
        var matches: [(id: String, text: String, range: NSRange)] = []
        for (id, original) in segments {
            let value = original as NSString
            var remaining = NSRange(location: 0, length: value.length)
            while remaining.length > 0 {
                let range = value.range(of: text, options: .literal, range: remaining)
                guard range.location != NSNotFound else { break }
                matches.append((id, original, range))
                if matches.count > 1 { return matches }
                let next = range.location + 1
                remaining = NSRange(location: next, length: value.length - next)
            }
        }
        return matches
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
