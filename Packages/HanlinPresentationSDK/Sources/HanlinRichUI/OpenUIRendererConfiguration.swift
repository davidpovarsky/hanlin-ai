#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import HanlinPresentationKit

/// A host may bundle its own versioned upstream library extension and supply
/// native mappings. These assets are trusted application code, never model output.
@MainActor public struct OpenUIRendererConfiguration {
    public let resourceDirectory: URL?
    public let nativeComponent: ((OpenUINativeElement, OpenUINativeActions) -> AnyView?)?
    public init(resourceDirectory: URL? = OpenUICatalogs.resourceDirectory,
                nativeComponent: ((OpenUINativeElement, OpenUINativeActions) -> AnyView?)? = nil) {
        self.resourceDirectory = resourceDirectory; self.nativeComponent = nativeComponent
    }
    public static var bundled: Self { .init(resourceDirectory: OpenUICatalogs.resourceDirectory) }
}

public struct OpenUINativeElement: Sendable {
    public let id: String
    public let typeName: String
    public let properties: [String: PresentationValue]
    public let isEnabled: Bool
}

@MainActor public struct OpenUINativeActions {
    private let write: (PresentationValue) -> Void
    private let trigger: () -> Void
    init(write: @escaping (PresentationValue) -> Void, trigger: @escaping () -> Void) {
        self.write = write; self.trigger = trigger
    }
    public func setValue(_ value: PresentationValue) { write(value) }
    public func performAction() { trigger() }
}
#endif
