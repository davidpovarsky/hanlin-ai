import Foundation

enum SefariaImports {
    static let capabilities: [NativeCapabilityRequest] = [
        .network(domain: "www.sefaria.org", reason: "Searches and opens Jewish text sources from Sefaria."),
        .pasteboardWrite(reason: "Copies source references or text from the Sefaria app.", optional: true)
    ]
}
