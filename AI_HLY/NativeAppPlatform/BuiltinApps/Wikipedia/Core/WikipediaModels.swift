import Foundation

struct WikipediaSearchResult: Identifiable, Hashable, Codable {
    var id: String { title }
    let title: String
    let description: String
    let url: URL?
}

struct WikipediaSummary: Identifiable, Hashable, Codable {
    var id: String { title }
    let title: String
    let extract: String
    let description: String?
    let url: URL?
    let thumbnailURL: URL?
}
