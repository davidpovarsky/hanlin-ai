import Foundation

enum WikipediaImports {
    static let capabilities: [NativeCapabilityRequest] = [
        .network(domain: "wikipedia.org", reason: "Searches and opens Wikipedia articles.")
    ]
}
