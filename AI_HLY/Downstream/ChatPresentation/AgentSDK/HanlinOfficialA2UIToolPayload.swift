#if HANLIN_A2UI_POC
import Foundation
import HanlinPlatformContracts

extension HanlinEmbeddedResultPayload {
    /// Explicit transport of original official envelopes through the existing result payload.
    /// Bytes stay bytes; arbitrary tool text/JSON is never inferred to be a renderer.
    static func officialA2UI(messages: [Data], title: String? = nil) throws -> Self {
        guard !messages.isEmpty, messages.count <= 64 else { throw HanlinA2UIIngress.Rejection(.sessionBudget) }
        for message in messages { _ = try HanlinA2UIIngress.inspect(message) }
        return .init(payload: .array(messages.map { .data($0) }), title: title,
            metadata: ["a2uiProtocolVersion": "1.0"])
    }

    var officialA2UIMessages: [Data]? {
        guard metadata?["a2uiProtocolVersion"] == "1.0", let payload, case .array(let values) = payload,
              !values.isEmpty, values.count <= 64 else { return nil }
        var messages: [Data] = []
        for value in values {
            guard case .data(let bytes) = value, (try? HanlinA2UIIngress.inspect(bytes)) != nil else { return nil }
            messages.append(bytes)
        }
        return messages
    }
}
#endif
