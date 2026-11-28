import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GenizahManuscriptRecord: Codable, Hashable, Sendable {
    public let sysID: String
    public let shelfmark: String
    public let library: String
    public let transcription: String?
    public let imageURL: String?
    public let description: String?

    public init(
        sysID: String,
        shelfmark: String,
        library: String,
        transcription: String? = nil,
        imageURL: String? = nil,
        description: String? = nil
    ) {
        self.sysID = sysID
        self.shelfmark = shelfmark
        self.library = library
        self.transcription = transcription
        self.imageURL = imageURL
        self.description = description
    }
}

public final class GenizahLibraryProvider: TorahLibraryProvider, @unchecked Sendable {
    public let providerID = "genizah"
    public let displayName = "Cairo Genizah Research"
    private let baseURL: URL

    public init(baseURL: URL = URL(string: "https://api.genizah.org/v1")!) {
        self.baseURL = baseURL
    }

    public func search(query: String, limit: Int = 5) async throws -> [TorahSearchHit] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL.absoluteString)/search?q=\(encoded)&mode=fuzzy&limit=\(limit)") else {
            return []
        }

        guard let data = try? await performRequest(url: url) else {
            return []
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item in
            guard let sysID = item["sys_id"] as? String,
                  let shelfmark = item["shelfmark"] as? String else { return nil }
            let snippet = (item["snippet"] as? String) ?? (item["transcription"] as? String) ?? shelfmark
            let locator = SourceLocator(
                providerID: self.providerID,
                corpusID: "cairo_genizah",
                workKey: sysID,
                positionKind: .segment,
                positionValue: sysID
            )
            return TorahSearchHit(
                locator: locator,
                workTitle: "Genizah: \(shelfmark)",
                textSnippet: snippet,
                fullText: item["transcription"] as? String,
                providerScore: 0.85
            )
        }
    }

    public func getSection(locator: SourceLocator) async throws -> StudySource? {
        guard let url = URL(string: "\(baseURL.absoluteString)/browse?sys_id=\(locator.positionValue)") else {
            return nil
        }
        guard let data = try? await performRequest(url: url) else {
            return nil
        }
        guard let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let shelfmark = (item["shelfmark"] as? String) ?? locator.workKey
        let library = (item["library"] as? String) ?? "Unknown Collection"
        let transcription = (item["transcription"] as? String) ?? (item["snippet"] as? String) ?? "No transcription available."

        return StudySource(
            locator: locator,
            primaryText: transcription,
            contextBefore: nil,
            contextAfter: nil,
            links: [],
            topics: [],
            versionMetadata: VersionMetadata(versionTitle: "Genizah Manuscript \(shelfmark)", language: "he"),
            licenseMetadata: LicenseMetadata(licenseName: "CC BY-NC-SA 4.0", copyrightNotice: "Attribution: \(library)"),
            provenance: "cairo_genizah_api"
        )
    }

    public func getLinks(locator: SourceLocator, type: String? = nil) async throws -> [TorahLinkedSource] {
        []
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
