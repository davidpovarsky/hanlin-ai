import Foundation

enum NativeAppWikipediaImports {
    static let capabilities: [NativeCapabilityRequest] = [
        .network(domain: "wikipedia.org", reason: "Searches and opens Wikipedia articles."),
        .pasteboardWrite(reason: "Copies article summaries.", optional: true)
    ]
}
