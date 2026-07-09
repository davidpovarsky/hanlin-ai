import Foundation

enum TextToolkitImports {
    static let capabilities: [NativeCapabilityRequest] = [
        .pasteboardRead(reason: "Can analyze text copied by the user.", optional: true),
        .pasteboardWrite(reason: "Can copy transformed text back to the clipboard.", optional: true)
    ]
}
