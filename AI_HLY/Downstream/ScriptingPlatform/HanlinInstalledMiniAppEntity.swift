import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
#if DEBUG || HANLIN_TESTING
import OSLog
#endif

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
        #if DEBUG || HANLIN_TESTING
        let traceLogger = Logger(subsystem: "com.hanlin.ai", category: "MiniAppsCatalog")
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        func trace(_ phase: String) {
            let elapsed = ProcessInfo.processInfo.systemUptime - traceStart
            traceLogger.notice("miniapps.catalog.spotlight.callback-selected id=\(traceID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) elapsed=\(elapsed, privacy: .public) phase=\(phase, privacy: .public)")
        }
        trace("begin")
        defer { trace("exit") }
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("reconcile.begin")
        #endif
        try await reconcileSpotlight()
        #if DEBUG || HANLIN_TESTING
        trace("reconcile.returned")
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("ack.return.ready")
        #endif
    }

    public nonisolated func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        #if DEBUG || HANLIN_TESTING
        let traceLogger = Logger(subsystem: "com.hanlin.ai", category: "MiniAppsCatalog")
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        func trace(_ phase: String) {
            let elapsed = ProcessInfo.processInfo.systemUptime - traceStart
            traceLogger.notice("miniapps.catalog.spotlight.callback-all id=\(traceID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) elapsed=\(elapsed, privacy: .public) phase=\(phase, privacy: .public)")
        }
        trace("begin")
        defer { trace("exit") }
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("reconcile.begin")
        #endif
        try await reconcileSpotlight()
        #if DEBUG || HANLIN_TESTING
        trace("reconcile.returned")
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("ack.return.ready")
        #endif
    }

    @MainActor
    private func reconcileSpotlight() async throws {
        #if DEBUG || HANLIN_TESTING
        let traceLogger = Logger(subsystem: "com.hanlin.ai", category: "MiniAppsCatalog")
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        func trace(_ phase: String) {
            let elapsed = ProcessInfo.processInfo.systemUptime - traceStart
            traceLogger.notice("miniapps.catalog.spotlight.query-reconcile id=\(traceID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) elapsed=\(elapsed, privacy: .public) phase=\(phase, privacy: .public)")
        }
        trace("begin")
        defer { trace("exit") }
        #endif
        // The SDK's non-Sendable index description stays with the protocol
        // caller. Only the existing catalog/index work enters the main actor.
        // A complete reconciliation also removes entities that were disabled or
        // uninstalled while Spotlight retained an older identifier.
        #if DEBUG || HANLIN_TESTING
        trace("current-records.begin")
        #endif
        _ = await currentRecords()
        #if DEBUG || HANLIN_TESTING
        trace("current-records.returned")
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("reindex.begin")
        #endif
        try await HanlinMiniAppSystemEntrypoints.shared.reindexSpotlight()
        #if DEBUG || HANLIN_TESTING
        trace("reindex.returned")
        #endif
    }

    @MainActor
    private func currentRecords() async -> [HanlinMiniAppSystemRecord] {
        #if DEBUG || HANLIN_TESTING
        let traceLogger = Logger(subsystem: "com.hanlin.ai", category: "MiniAppsCatalog")
        let traceID = UUID().uuidString
        let traceStart = ProcessInfo.processInfo.systemUptime
        func trace(_ phase: String) {
            let elapsed = ProcessInfo.processInfo.systemUptime - traceStart
            traceLogger.notice("miniapps.catalog.spotlight.current-records id=\(traceID, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) elapsed=\(elapsed, privacy: .public) phase=\(phase, privacy: .public)")
        }
        trace("begin")
        defer { trace("exit") }
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("restore.begin")
        #endif
        await HanlinScriptingPlatform.shared.restore()
        #if DEBUG || HANLIN_TESTING
        trace("restore.returned")
        #endif
        #if DEBUG || HANLIN_TESTING
        trace("return.ready")
        #endif
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
