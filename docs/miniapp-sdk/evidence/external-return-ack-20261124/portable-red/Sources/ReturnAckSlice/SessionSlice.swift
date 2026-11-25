import Foundation

// Foundation-only projection. Methods below are verbatim production excerpts.
// No native engine/presenter implementation is replaced or claimed to execute.
@MainActor
final class HanlinExternalMiniAppSession {
    let requestID: UUID
    private(set) var request: MiniAppInvocation?
    private(set) var result: MiniAppResult?
    private(set) var returning = false
    var error: String?
    private let storeOverride: MiniAppBridgeStore?
    private let openSource: @MainActor (URL) async -> Bool
    private(set) var cleanupCalls = 0
    init(requestID: UUID, store: MiniAppBridgeStore?,
         openSource: @escaping @MainActor (URL) async -> Bool) {
        self.requestID = requestID; self.storeOverride = store; self.openSource = openSource
    }
    private func releaseEngine() { cleanupCalls += 1 }
    private func mailbox() throws -> MiniAppBridgeStore {
        if let storeOverride { return storeOverride }
        return try MiniAppBridgeStore()
    }

    func restoreRequest() throws -> MiniAppInvocation {
        guard let request = try mailbox().request(id: requestID) else {
            throw failure("The shared request could not be found.")
        }
        self.request = request
        self.result = try mailbox().result(id: requestID)
        return request
    }

    func perform(_ operation: String, payload: String) async throws -> String {
        guard let request else { throw failure("The shared request is not ready.") }
        switch operation {
        case "miniapps.context":
            return String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        case "miniapps.readAttachment":
            let input = try JSONDecoder().decode([String: String].self, from: Data(payload.utf8))
            guard let rawID = input["id"], let id = UUID(uuidString: rawID) else {
                throw MiniAppBridgeError.invalidAttachment
            }
            let data = try Data(contentsOf: mailbox().attachmentURL(id: id))
            return String(decoding: try JSONEncoder().encode(["base64": data.base64EncodedString()]), as: UTF8.self)
        case "miniapps.writeAttachment":
            let input = try JSONDecoder().decode([String: String].self, from: Data(payload.utf8))
            guard let base64 = input["base64"], let data = Data(base64Encoded: base64) else {
                throw MiniAppBridgeError.invalidAttachment
            }
            let item = try mailbox().writeAttachment(data, name: input["name"], typeIdentifier: input["typeIdentifier"])
            return String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        case "miniapps.complete":
            try await completeJSON(Data(payload.utf8), returnsToSource: false)
            return #"{"ok":true}"#
        case "miniapps.cancel":
            try await finish(MiniAppResult(requestID: request.id, status: .cancelled), returnsToSource: false)
            return #"{"ok":true}"#
        case "miniapps.return":
            await returnToSource()
            releaseEngine()
            return #"{"ok":true}"#
        default:
            throw failure("Unknown MiniApps operation.")
        }
    }

    func returnToSource() async {
        guard !returning, let request, let result else { return }
        guard let url = request.callbackURL(for: result) else { return }
        returning = true
        defer { returning = false }
        let opened = await openSource(url)
        if !opened {
            error = Self.localized("The result is saved. Open the source app to continue.",
                                   "התוצאה נשמרה. יש לפתוח את אפליקציית המקור כדי להמשיך.")
        }
    }

    private func completeJSON(_ data: Data, returnsToSource: Bool = true) async throws {
        guard let request else { throw failure("The shared request is not ready.") }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let receipt: MiniAppResult
        if let text = value as? String {
            receipt = MiniAppResult(requestID: request.id, operation: request.operation,
                items: [.init(kind: .text, text: text, typeIdentifier: "public.utf8-plain-text")])
        } else if var object = value as? [String: Any] {
            // Scripts provide output; the host supplies correlation and origin.
            object["requestID"] = request.id.uuidString
            object["status"] = object["status"] ?? "success"
            object["operation"] = object["operation"] ?? request.operation.rawValue
            object["items"] = object["items"] ?? []
            object["metadata"] = object["metadata"] ?? [:]
            let encoded = try JSONSerialization.data(withJSONObject: object)
            receipt = try JSONDecoder().decode(MiniAppResult.self, from: encoded)
        } else {
            receipt = MiniAppResult(requestID: request.id, operation: .display,
                items: [.init(kind: .json, text: String(decoding: data, as: UTF8.self),
                              typeIdentifier: "public.json")])
        }
        try await finish(receipt, returnsToSource: returnsToSource)
    }

    private func finish(_ receipt: MiniAppResult, returnsToSource: Bool = true) async throws {
        let mailbox = try mailbox()
        if let saved = try mailbox.result(id: requestID) {
            result = saved
        } else {
            try mailbox.complete(receipt)
            result = receipt
        }
        if returnsToSource {
            await returnToSource()
            releaseEngine()
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "HanlinMiniApps.CrossApp", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func localized(_ english: String, _ hebrew: String) -> String {
        Locale.current.language.languageCode?.identifier == "he" ? hebrew : english
    }
}
