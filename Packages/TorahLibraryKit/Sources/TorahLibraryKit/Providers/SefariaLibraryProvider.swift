import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class SefariaLibraryProvider: TorahLibraryProvider, @unchecked Sendable {
    public let providerID = "sefaria"
    public let displayName = "Sefaria"
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "https://www.sefaria.org/api")!) {
        self.baseURL = baseURL
    }

    public func search(query: String, limit: Int = 10) async throws -> [TorahSearchHit] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL.absoluteString)/search-wrapper?q=\(encoded)&size=\(limit)") else {
            return []
        }

        guard let data = try? await performRequest(url: url) else {
            return []
        }

        struct SefariaSearchResponse: Decodable {
            struct Hit: Decodable {
                struct Source: Decodable {
                    let ref: String?
                    let heRef: String?
                    let exact: String?
                    let naive_lemmatizer: String?
                }
                let _source: Source?
            }
            struct Hits: Decodable {
                let hits: [Hit]?
            }
            let hits: Hits?
        }

        guard let parsed = try? JSONDecoder().decode(SefariaSearchResponse.self, from: data),
              let hitsList = parsed.hits?.hits else {
            return []
        }

        return hitsList.compactMap { hit in
            guard let src = hit._source, let ref = src.ref else { return nil }
            let snippet = src.exact ?? src.naive_lemmatizer ?? ref
            let locator = SourceLocator(
                providerID: self.providerID,
                corpusID: "sefaria_canonical",
                workKey: ref,
                positionKind: .canonicalRef,
                positionValue: ref
            )
            return TorahSearchHit(
                locator: locator,
                workTitle: src.heRef ?? ref,
                textSnippet: snippet,
                fullText: nil,
                providerScore: 0.9
            )
        }
    }

    public func getSection(locator: SourceLocator) async throws -> StudySource? {
        guard let encoded = locator.positionValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL.absoluteString)/texts/\(encoded)?context=1") else {
            return nil
        }

        guard let data = try? await performRequest(url: url) else {
            return nil
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let ref = (obj["ref"] as? String) ?? locator.positionValue
        let heRef = obj["heRef"] as? String
        var heText = ""
        if let heArray = obj["he"] as? [String] {
            heText = heArray.joined(separator: "\n")
        } else if let heStr = obj["he"] as? String {
            heText = heStr
        }

        var enText = ""
        if let enArray = obj["text"] as? [String] {
            enText = enArray.joined(separator: "\n")
        } else if let enStr = obj["text"] as? String {
            enText = enStr
        }

        let primary = !heText.isEmpty ? heText : enText
        let versionTitle = (obj["versionTitle"] as? String) ?? "Sefaria Edition"
        let license = (obj["license"] as? String) ?? "Public Domain / CC"

        return StudySource(
            locator: locator,
            primaryText: primary,
            contextBefore: nil,
            contextAfter: nil,
            links: [],
            topics: [],
            versionMetadata: VersionMetadata(versionTitle: versionTitle, versionTitleInHebrew: heRef, language: "he"),
            licenseMetadata: LicenseMetadata(licenseName: license, copyrightNotice: nil),
            provenance: "sefaria_api"
        )
    }

    public func getLinks(locator: SourceLocator, type: String? = nil) async throws -> [TorahLinkedSource] {
        guard let encoded = locator.positionValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL.absoluteString)/links/\(encoded)") else {
            return []
        }

        guard let data = try? await performRequest(url: url) else {
            return []
        }

        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { item in
            guard let ref = item["ref"] as? String else { return nil }
            let category = (item["category"] as? String) ?? "Commentary"
            let itemType = (item["type"] as? String) ?? "commentary"
            let collectiveTitle = item["collectiveTitle"] as? [String: String]
            let enTitle = collectiveTitle?["en"]
            let heTitle = collectiveTitle?["he"]
            let heText = item["he"] as? String
            let enText = item["text"] as? String

            if let targetType = type, !itemType.localizedCaseInsensitiveContains(targetType) {
                return nil
            }

            return TorahLinkedSource(
                sourceRef: ref,
                sourceHebrewRef: item["heRef"] as? String,
                category: category,
                type: itemType,
                collectiveTitle: enTitle,
                hebrewCollectiveTitle: heTitle,
                hebrewText: heText,
                englishText: enText,
                versionTitle: item["versionTitle"] as? String,
                license: item["license"] as? String,
                provenance: "sefaria_links"
            )
        }
    }

    public func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic] {
        []
    }

    private func performRequest(url: URL) async throws -> Data {
        #if canImport(Darwin)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ITorahSharedStorageError.directoryNotFound("HTTP request failed")
        }
        return data
        #else
        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.dataTask(with: url) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
                    continuation.resume(throwing: ITorahSharedStorageError.directoryNotFound("HTTP request failed"))
                    return
                }
                continuation.resume(returning: data)
            }
            task.resume()
        }
        #endif
    }
}
