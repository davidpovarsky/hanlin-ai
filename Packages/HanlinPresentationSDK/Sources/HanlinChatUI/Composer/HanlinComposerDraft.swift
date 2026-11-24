import Foundation
import Observation

#if canImport(UIKit)
/// The original Hanlin draft owner shared by the app and independently embedded composers.
/// Binding writes and the native editor's synchronous state reader use this same reference.
@MainActor
@Observable
public final class HanlinComposerDraft {
    public private(set) var snapshot: NativeMultilineTextEditor.TextState

    public var text: String {
        get { snapshot.text }
        set {
            snapshot = .init(ownerID: snapshot.ownerID, revision: UUID(), text: newValue)
        }
    }

    public init(text: String = "") {
        snapshot = .init(ownerID: UUID(), revision: UUID(), text: text)
    }
}
#endif
