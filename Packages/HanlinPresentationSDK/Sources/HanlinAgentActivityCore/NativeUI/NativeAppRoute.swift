import Foundation


public struct NativeAppRoute: Identifiable, Codable, Hashable {
    public var id: String {
        [appID, screen, stablePayloadID].filter { !$0.isEmpty }.joined(separator: ":")
    }

    public let appID: String
    public let screen: String
    public let payload: NativeAppRoutePayload

    public init(appID: String, screen: String, payload: NativeAppRoutePayload = .empty) {
        self.appID = appID
        self.screen = screen
        self.payload = payload
    }

    private var stablePayloadID: String {
        switch payload {
        case .empty:
            return ""
        case .dictionary(let values):
            return values.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
        }
    }
}

public enum NativeAppRoutePayload: Codable, Hashable {
    case empty
    case dictionary([String: String])

    public var values: [String: String] {
        switch self {
        case .empty: return [:]
        case .dictionary(let values): return values
        }
    }

    public func string(_ key: String) -> String? { values[key] }
}
