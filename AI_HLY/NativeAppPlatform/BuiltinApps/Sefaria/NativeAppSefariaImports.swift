import Foundation

enum NativeAppSefariaImports {
    static let capabilities: [NativeCapabilityRequest] = [
        .network(domain: "sefaria.org", reason: "Searches and opens Jewish texts."),
        .pasteboardWrite(reason: "Copies references and source text.", optional: true)
    ]
}
