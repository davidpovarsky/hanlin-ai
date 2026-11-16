#if HANLIN_A2UI_POC
import Foundation
import HanlinPlatformContracts

/// The native schema producer invokes this before publishing or persisting any complete batch.
/// It has no live store, Session, host, view, network loader or interaction admission.
@MainActor
enum HanlinA2UICompleteBatchValidator {
    enum Failure: Error, Equatable {
        case emptyBatch, resourceLimit, invalidSequence, unsupportedProtocol, invalidFrame, incompleteGraph
    }
    private struct Owner: Hashable { let messageID: UUID; let partID: UUID }

    static func validate(_ parts: [HanlinChatStructuredPart]) throws {
        try validate(parts, onDisposing: nil)
    }

    private static func validate(_ parts: [HanlinChatStructuredPart],
                                 onDisposing: ((HanlinA2UISession) -> Void)?) throws {
        guard !parts.isEmpty else { throw Failure.emptyBatch }
        guard parts.count <= HanlinA2UIContentLimits.maximumFrames else { throw Failure.resourceLimit }
        var sequence = HanlinChatStructuredPartSequence()
        var ids: [UUID: Set<UUID>] = [:]
        var textBytes: [UUID: Int] = [:]
        var wireBytes = 0
        var frames: [Owner: [String]] = [:]
        var owners: [Owner] = []
        // Validate the entire canonical order and framing before constructing scratch models.
        for part in parts {
            let bytes: Int
            switch part.payload {
            case .textDelta(let text): bytes = text.utf8.count
            case .a2uiMessage(_, let data): bytes = data.count
            }
            guard bytes <= HanlinA2UIContentLimits.maximumWireBytes - wireBytes else { throw Failure.resourceLimit }
            wireBytes += bytes
            let admitted: Bool
            do { admitted = try sequence.admit(part) } catch { throw Failure.invalidSequence }
            if !admitted { continue } // Identical canonical replay cannot apply an update twice.
            guard ids[part.messageID] != nil || ids.count < HanlinA2UIContentLimits.maximumMessages else { throw Failure.resourceLimit }
            ids[part.messageID, default: []].insert(part.partID)
            guard ids[part.messageID, default: []].count <= HanlinA2UIContentLimits.maximumPartsPerMessage else { throw Failure.resourceLimit }
            switch part.payload {
            case .textDelta(let text):
                let used = textBytes[part.messageID, default: 0]
                guard text.utf8.count <= HanlinA2UIContentLimits.maximumTextBytesPerMessage - used else { throw Failure.resourceLimit }
                textBytes[part.messageID] = used + text.utf8.count
            case .a2uiMessage(let version, let data):
                guard version == "1.0" else { throw Failure.unsupportedProtocol }
                let json: String
                do {
                    _ = try HanlinA2UIIngress.inspect(data)
                    guard let value = String(data: data, encoding: .utf8) else { throw Failure.invalidFrame }
                    json = value
                } catch { throw Failure.invalidFrame }
                let owner = Owner(messageID: part.messageID, partID: part.partID)
                if frames[owner] == nil { owners.append(owner) }
                frames[owner, default: []].append(json)
            }
        }
        // Owners may reuse wire surface IDs. Keep one official processor alive at a time;
        // both normal return and every thrown error dispose subscriptions/models/pending calls.
        for owner in owners {
            let scratch = HanlinA2UISession(onEvent: { _ in })
            defer { onDisposing?(scratch); scratch.close() }
            var lifetime = HanlinA2UIFrameLifetime()
            for json in frames[owner, default: []] {
                if case .failure = lifetime.receive(json, in: scratch) { throw Failure.invalidFrame }
            }
            do { try scratch.validateCompleteGraphs() } catch { throw Failure.incompleteGraph }
        }
    }

    #if DEBUG
    /// Observation only for disposal/no-effects tests. The production entry point has no hook.
    static func validateForLifecycleTests(_ parts: [HanlinChatStructuredPart],
                                         onDisposing: @escaping (HanlinA2UISession) -> Void) throws {
        try validate(parts, onDisposing: onDisposing)
    }
    #endif
}
#endif
