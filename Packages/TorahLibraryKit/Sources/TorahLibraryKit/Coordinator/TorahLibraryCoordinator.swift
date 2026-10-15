import Foundation

/// Provider deployment role in the Torah Study system.
public enum TorahProviderRole: String, Codable, Sendable {
    case local
    case remote
    case enrichment
}

/// Provider descriptor with live availability status.
public struct TorahProviderStatus: Sendable {
    public let providerID: String
    public let displayName: String
    public let role: TorahProviderRole
    public let isAvailable: Bool
    public let provenance: String
}

/// Errors thrown by the unified Torah library coordinator.
public enum TorahCoordinatorError: LocalizedError, Sendable {
    case providerNotFound(String)
    case sourceNotFound(SourceLocator)
    case allProvidersUnavailable
    case invalidLocator(String)

    public var errorDescription: String? {
        switch self {
        case .providerNotFound(let id):
            return "Torah provider '\(id)' is not registered or supported."
        case .sourceNotFound(let loc):
            return "Torah source could not be resolved for locator: \(loc.persistenceKey)"
        case .allProvidersUnavailable:
            return "No Torah corpus providers are currently available (local corpus not installed and remote offline)."
        case .invalidLocator(let details):
            return "Invalid source locator format: \(details)"
        }
    }
}

/// Authoritative production coordinator and registry for Torah corpus providers.
/// Enforces local-first search hierarchy:
/// 1. Local Otzaria / Zayit exact search (offline, on-device SQLite / Tantivy)
/// 2. Local fuzzy / advanced retrieval
/// 3. Sefaria remote fallback where available
public final class TorahLibraryCoordinator: @unchecked Sendable {
    public static let shared = TorahLibraryCoordinator()

    public let otzariaProvider: OtzariaLibraryProvider
    public let zayitProvider: ZayitLibraryProvider
    public let sefariaProvider: SefariaLibraryProvider
    public let genizahProvider: GenizahLibraryProvider

    private let lock = NSLock()
    private var customProviders: [String: any TorahLibraryProvider] = [:]

    public init(
        otzariaProvider: OtzariaLibraryProvider = OtzariaLibraryProvider(),
        zayitProvider: ZayitLibraryProvider = ZayitLibraryProvider(),
        sefariaProvider: SefariaLibraryProvider = SefariaLibraryProvider(),
        genizahProvider: GenizahLibraryProvider = GenizahLibraryProvider()
    ) {
        self.otzariaProvider = otzariaProvider
        self.zayitProvider = zayitProvider
        self.sefariaProvider = sefariaProvider
        self.genizahProvider = genizahProvider
    }

    public var isLocalCorpusAvailable: Bool {
        otzariaProvider.isAvailable || zayitProvider.isAvailable
    }

    public func providerStatuses() -> [TorahProviderStatus] {
        [
            TorahProviderStatus(
                providerID: otzariaProvider.providerID,
                displayName: otzariaProvider.displayName,
                role: .local,
                isAvailable: otzariaProvider.isAvailable,
                provenance: otzariaProvider.databaseURL?.path ?? "uninstalled"
            ),
            TorahProviderStatus(
                providerID: zayitProvider.providerID,
                displayName: zayitProvider.displayName,
                role: .local,
                isAvailable: zayitProvider.isAvailable,
                provenance: zayitProvider.searchIndexURL?.path ?? "uninstalled"
            ),
            TorahProviderStatus(
                providerID: sefariaProvider.providerID,
                displayName: sefariaProvider.displayName,
                role: .remote,
                isAvailable: true,
                provenance: "https://www.sefaria.org/api"
            ),
            TorahProviderStatus(
                providerID: genizahProvider.providerID,
                displayName: genizahProvider.displayName,
                role: .enrichment,
                isAvailable: true,
                provenance: "https://api.genizah.org/v1"
            )
        ]
    }

    // MARK: - Source Identification

    /// Identifies a photographed excerpt using real local-first corpus ranking.
    /// Does not require internet when the local corpus is installed.
    public func identifyExcerpt(
        evidence: OCREvidence,
        allowRemoteFallback: Bool = true
    ) async -> IdentificationResult {
        var localEngines: [any TorahLibrarySearchEngine] = []

        if otzariaProvider.isAvailable {
            localEngines.append(otzariaProvider)
        }
        if zayitProvider.isAvailable {
            localEngines.append(zayitProvider)
        }

        // 1. Try local engines first (Otzaria / Zayit offline on-device)
        if !localEngines.isEmpty {
            let localResolver = TorahSourceResolver(searchEngines: localEngines)
            let localResult = await localResolver.resolve(evidence: evidence)
            if localResult.status == .verified || localResult.status == .ambiguous {
                return localResult
            }
        }

        // 2. Remote Sefaria fallback if permitted
        if allowRemoteFallback {
            let remoteResolver = TorahSourceResolver(searchEngines: [sefariaProvider])
            return await remoteResolver.resolve(evidence: evidence)
        }

        return IdentificationResult(
            status: .notFound,
            candidates: [],
            searchedCorpora: localEngines.map { String(describing: type(of: $0)) },
            warnings: ["Excerpt could not be verified in local corpus and remote fallback was disabled."],
            requestID: UUID().uuidString
        )
    }

    // MARK: - Search

    /// Multi-provider search respecting requested provider list and mode.
    public func search(
        query: String,
        providers: [String] = [],
        mode: String = "exact",
        limit: Int = 10
    ) async throws -> [TorahSearchHit] {
        let requested = Set(providers.map { $0.lowercased() })
        var hits: [TorahSearchHit] = []
        var seenLocators = Set<String>()

        // 1. Local Otzaria
        if requested.isEmpty || requested.contains("otzaria") {
            if otzariaProvider.isAvailable {
                let localHits = try await otzariaProvider.search(query: query, limit: limit)
                for hit in localHits where !seenLocators.contains(hit.locator.persistenceKey) {
                    seenLocators.insert(hit.locator.persistenceKey)
                    hits.append(hit)
                }
            }
        }

        // 2. Local Zayit
        if requested.isEmpty || requested.contains("zayit") {
            if zayitProvider.isAvailable && hits.count < limit {
                let zayitHits = try await zayitProvider.search(query: query, limit: limit - hits.count)
                for hit in zayitHits where !seenLocators.contains(hit.locator.persistenceKey) {
                    seenLocators.insert(hit.locator.persistenceKey)
                    hits.append(hit)
                }
            }
        }

        // 3. Remote Sefaria
        if requested.isEmpty || requested.contains("sefaria") {
            if hits.count < limit {
                let sefariaHits = try await sefariaProvider.search(query: query, limit: limit - hits.count)
                for hit in sefariaHits where !seenLocators.contains(hit.locator.persistenceKey) {
                    seenLocators.insert(hit.locator.persistenceKey)
                    hits.append(hit)
                }
            }
        }

        // 4. Cairo Genizah
        if requested.contains("genizah") {
            if hits.count < limit {
                let genizahHits = try await genizahProvider.search(query: query, limit: limit - hits.count)
                for hit in genizahHits where !seenLocators.contains(hit.locator.persistenceKey) {
                    seenLocators.insert(hit.locator.persistenceKey)
                    hits.append(hit)
                }
            }
        }

        return hits
    }

    // MARK: - Section Retrieval

    /// Loads canonical source text strictly routing to the locator's matching provider.
    public func getSection(locator: SourceLocator) async throws -> StudySource {
        let providerID = locator.providerID.lowercased()

        if providerID == "otzaria" || providerID == "maktabah" {
            if let source = try await otzariaProvider.getSection(locator: locator) {
                return source
            }
            throw TorahCoordinatorError.sourceNotFound(locator)
        } else if providerID == "zayit" {
            if let source = try await zayitProvider.getSection(locator: locator) {
                return source
            }
            throw TorahCoordinatorError.sourceNotFound(locator)
        } else if providerID == "sefaria" {
            if let source = try await sefariaProvider.getSection(locator: locator) {
                return source
            }
            throw TorahCoordinatorError.sourceNotFound(locator)
        } else if providerID == "genizah" {
            if let source = try await genizahProvider.getSection(locator: locator) {
                return source
            }
            throw TorahCoordinatorError.sourceNotFound(locator)
        } else {
            throw TorahCoordinatorError.providerNotFound(locator.providerID)
        }
    }

    // MARK: - Links & Relationships

    public func getLinks(locator: SourceLocator, type: String? = nil) async throws -> [TorahLinkedSource] {
        let providerID = locator.providerID.lowercased()

        if providerID == "otzaria" || providerID == "zayit" {
            return try await otzariaProvider.getLinks(locator: locator, type: type)
        } else if providerID == "sefaria" {
            return try await sefariaProvider.getLinks(locator: locator, type: type)
        } else if providerID == "genizah" {
            return try await genizahProvider.getLinks(locator: locator, type: type)
        }
        return []
    }

    // MARK: - Topics

    public func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic] {
        let providerID = locator.providerID.lowercased()

        if providerID == "sefaria" {
            return try await sefariaProvider.getTopics(locator: locator)
        } else if providerID == "otzaria" {
            return try await otzariaProvider.getTopics(locator: locator)
        }
        return []
    }
}
