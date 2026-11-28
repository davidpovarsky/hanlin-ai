import Foundation

enum NativeAppTextStudioImports {
    static let capabilities: [NativeCapabilityRequest] = [
        .pasteboardRead(reason: "Imports text from the clipboard.", optional: true),
        .pasteboardWrite(reason: "Copies transformed text and analysis results.", optional: true)
    ]
}
