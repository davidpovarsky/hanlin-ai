import Foundation
import HanlinPlatformContracts
import HanlinScriptStore

/// Connects immutable ingress to the existing ResumeQueue. The Host must check
/// the selected installed identity/action both at selection and at dispatch.
public enum HanlinShareInvocation {
    public static func command(batch: HanlinShareBatch, identity: HanlinScriptExtensionIdentity,
                               appID: HanlinAppID, actionID: HanlinActionID) -> HanlinScriptResumeCommand {
        .init(id: batch.id, createdAt: batch.createdAt, invocation: .init(
            identity: identity, entityID: actionID.rawValue,
            parameters: .object(["shareBatchID": .string(batch.id.uuidString.lowercased())]),
            continueInForeground: true,
            delivery: .init(appID: appID, source: .share, expiresAt: batch.createdAt.addingTimeInterval(86_400),
                            expectedResult: .value, userGesturePresent: true, canPresentUI: false)))
    }

    /// Full text and attachments stay outside the256KiB queue envelope. Resolve
    /// the immutable batch only after target/generation validation; never trust
    /// file paths supplied by the caller. Each file's actual bytes are verified.
    public static func payload(for command: HanlinScriptResumeCommand, inbox: HanlinShareInboxStore) throws -> HanlinValue {
        guard command.invocation.delivery?.source == .share,
              command.invocation.parameters == .object(["shareBatchID": .string(command.id.uuidString.lowercased())]) else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        let batch = try inbox.batch(command.id)
        let items: [HanlinValue] = try batch.items.map { item in
            var value: [String: HanlinValue] = ["id": .string(item.id.uuidString.lowercased()),
                "ordinal": .integer(Int64(item.ordinal)), "kind": .string(item.content.rawValue),
                "typeIdentifier": .string(item.typeIdentifier)]
            if let name = item.name { value["name"] = .string(name) }
            if let text = item.text { value["text"] = .string(text) }
            if let failure = item.failure { value["failure"] = .string(failure.rawValue) }
            if item.content == .file {
                let url = try inbox.ownedFile(batchID: batch.id, itemID: item.id)
                value["fileURL"] = .string(url.absoluteString)
                if let bytes = item.bytes { value["bytes"] = .integer(bytes) }
                if let sha256 = item.sha256 { value["sha256"] = .string(sha256) }
            }
            return .object(value)
        }
        return .object(["shareBatchID": .string(batch.id.uuidString.lowercased()), "items": .array(items)])
    }
}
