import Foundation

struct NativeAppSefariaSearchResult: Identifiable, Hashable, Codable {
    var id: String { ref }
    let ref: String
    let title: String
    let snippet: String
    let url: URL?
}

struct NativeAppSefariaSource: Identifiable, Hashable, Codable {
    var id: String { ref }
    let ref: String
    let text: String
    let heText: String?
    let url: URL?
}
