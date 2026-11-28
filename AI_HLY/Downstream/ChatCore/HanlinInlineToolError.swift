import Foundation

struct HanlinInlineToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
