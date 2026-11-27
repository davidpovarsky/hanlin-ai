import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// An installed package's declared Spotlight entrypoint, independent of widgets.
public struct HanlinInstalledMiniAppEntity: IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Installed mini app")
    public static let defaultQuery = HanlinInstalledMiniAppQuery()

    public let id: String
    let title: String
    let summary: String
    let keywords: [String]
    let iconURL: URL?
    let symbolName: String?

    init(_ record: HanlinMiniAppSystemRecord) {
        id = record.id; title = record.title; summary = record.summary
        keywords = record.keywords; iconURL = record.iconURL; symbolName = record.symbolName
    }

    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(title)", subtitle: "\(summary)",
              image: .init(systemName: symbolName ?? "square.grid.2x2"))
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .application)
        attributes.title = title
        attributes.contentDescription = summary
        attributes.keywords = keywords
        attributes.thumbnailURL = iconURL
        return attributes
    }
}

public struct HanlinInstalledMiniAppQuery: EnumerableEntityQuery, EntityStringQuery, IndexedEntityQuery {
    public init() {}
    @MainActor
    public func entities(for identifiers: [String]) async throws -> [HanlinInstalledMiniAppEntity] {
        let records = await currentRecords()
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(HanlinInstalledMiniAppEntity.init) }
    }

    @MainActor
    public func allEntities() async throws -> [HanlinInstalledMiniAppEntity] {
        await currentRecords().map(HanlinInstalledMiniAppEntity.init)
    }

    @MainActor
    public func suggestedEntities() async throws -> [HanlinInstalledMiniAppEntity] { try await allEntities() }

    @MainActor
    public func entities(matching string: String) async throws -> [HanlinInstalledMiniAppEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return await currentRecords().filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
            $0.summary.localizedCaseInsensitiveContains(query) ||
            $0.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }.map(HanlinInstalledMiniAppEntity.init)
    }

    public nonisolated func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await reconcileSpotlight()
    }

    public nonisolated func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await reconcileSpotlight()
    }

    @MainActor
    private func reconcileSpotlight() async throws {
        // The SDK's non-Sendable index description stays with the protocol
        // caller. Only the existing catalog/index work enters the main actor.
        // A complete reconciliation also removes entities that were disabled or
        // uninstalled while Spotlight retained an older identifier.
        _ = await currentRecords()
        try await HanlinMiniAppSystemEntrypoints.shared.reindexSpotlight()
    }

    @MainActor
    private func currentRecords() async -> [HanlinMiniAppSystemRecord] {
        await HanlinScriptingPlatform.shared.restore()
        return HanlinMiniAppSystemEntrypoints.shared.spotlightRecords
    }
}

/// OpenIntent gives Spotlight the supported foreground action for this entity.
/// The indexed title never supplies a file path or an executable handler.
public struct HanlinOpenInstalledMiniAppIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open installed mini app"
    @Parameter(title: "Mini app") public var target: HanlinInstalledMiniAppEntity

    public init() {}
    public init(target: HanlinInstalledMiniAppEntity) { self.target = target }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try await HanlinMiniAppSystemEntrypoints.shared.openSpotlightEntity(id: target.id)
        return .result()
    }
}

public struct HanlinMiniAppSystemIntentsPackage: AppIntentsPackage {}
