import Foundation

struct NativeAppAppearance: Hashable, Codable {
    let startHex: String
    let endHex: String
    let foregroundHex: String

    init(startHex: String, endHex: String, foregroundHex: String = "FFFFFF") {
        self.startHex = startHex
        self.endHex = endHex
        self.foregroundHex = foregroundHex
    }
}
