import Foundation

public enum HanlinAppleProviderError: String, Error, LocalizedError, Sendable {
    case unavailable, unsupportedTools, unsupportedContent, unsupportedSettings, inconsistentSnapshot
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Intelligence is not available on this device right now."
        case .unsupportedTools: "On-device tool calling is not supported by this adapter version. Choose a model manually that supports the requested tools."
        case .unsupportedContent: "This on-device adapter accepts text conversations only."
        case .unsupportedSettings: "The requested generation settings are not supported by this on-device adapter."
        case .inconsistentSnapshot: "The on-device model returned an inconsistent streamed response."
        }
    }
}

/// Pure normalization, shared by the actual native adapter and portable behavioral proof.
public struct HanlinAppleTextDelta: Sendable {
    public private(set) var text = ""
    public init() {}
    public mutating func append(snapshot: String) throws -> String {
        // Grapheme counts/prefix equality can change when a streaming Hebrew vowel or other
        // combining mark joins the previous character. Preserve exact UTF-8 output instead.
        let previous = Array(text.utf8)
        let next = Array(snapshot.utf8)
        guard next.starts(with: previous) else { throw HanlinAppleProviderError.inconsistentSnapshot }
        let delta = String(decoding: next.dropFirst(previous.count), as: UTF8.self)
        text = snapshot
        return delta
    }
}
