#if HANLIN_A2UI_POC
import Foundation
import SwiftUI

/// Explicit presentation injection for already-registered results. This does not register,
/// receive, infer a renderer from payload/text, or follow a replacement into a new generation.
@MainActor
final class HanlinA2UIResultProjectionSource {
    private struct Identity: Hashable {
        let runID: UUID
        let resultID: UUID
        let callID: String
    }
    private weak var store: HanlinA2UIResultStore?
    private let keys: [Identity: HanlinA2UIResultKey]

    init?(store: HanlinA2UIResultStore, keys: [HanlinA2UIResultKey]) {
        var registered: [Identity: HanlinA2UIResultKey] = [:]
        for key in keys {
            let identity = Identity(runID: key.runID, resultID: key.resultID, callID: key.callID)
            guard registered[identity] == nil, store.projection(for: key) != nil else { return nil }
            registered[identity] = key
        }
        self.store = store
        self.keys = registered
    }

    func projection(runID: UUID?, resultID: UUID, callID: String?) -> HanlinA2UIResultProjection? {
        guard let runID, let callID,
              let key = keys[Identity(runID: runID, resultID: resultID, callID: callID)],
              let projection = store?.projection(for: key), !projection.isClosed else { return nil }
        return projection
    }
}

extension EnvironmentValues {
    @Entry var hanlinA2UIResultProjectionSource: HanlinA2UIResultProjectionSource? = nil
}
#endif
