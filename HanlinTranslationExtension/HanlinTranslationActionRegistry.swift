import Foundation

struct HanlinTranslationActionDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let systemImage: String
}

/// The single exposure point for actions that are allowed to appear in the
/// system translation surface. Mini-app providers can be registered here in a
/// later phase without coupling their implementations to the extension scene.
protocol HanlinTranslationActionProviding: Sendable {
    func actions(for text: AttributedString?) -> [HanlinTranslationActionDescriptor]
}

struct HanlinTranslationActionRegistry: Sendable {
    static let standard = HanlinTranslationActionRegistry(
        providers: [HanlinCoreTranslationActions()]
    )

    private let providers: [any HanlinTranslationActionProviding]

    init(providers: [any HanlinTranslationActionProviding]) {
        self.providers = providers
    }

    func actions(for text: AttributedString?) -> [HanlinTranslationActionDescriptor] {
        guard let text, !text.characters.isEmpty else { return [] }
        return providers.flatMap { $0.actions(for: text) }
    }
}

private struct HanlinCoreTranslationActions: HanlinTranslationActionProviding {
    func actions(for text: AttributedString?) -> [HanlinTranslationActionDescriptor] {
        [
            HanlinTranslationActionDescriptor(
                id: "translate",
                title: "Translate",
                systemImage: "character.book.closed"
            )
        ]
    }
}
