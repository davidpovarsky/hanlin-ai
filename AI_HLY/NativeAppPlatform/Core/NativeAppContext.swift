import Foundation
import SwiftData
import SwiftUI

typealias NativeOpenURLAction = @MainActor (URL) -> Void

@MainActor
struct NativeAppContext {
    var localeIdentifier: String
    var modelContext: ModelContext?
    var openURL: NativeOpenURLAction?
    var capabilityRegistry: NativeCapabilityRegistry

    init(
        localeIdentifier: String = Locale.current.identifier,
        modelContext: ModelContext? = nil,
        openURL: NativeOpenURLAction? = nil,
        capabilityRegistry: NativeCapabilityRegistry? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.modelContext = modelContext
        self.openURL = openURL
        self.capabilityRegistry = capabilityRegistry ?? .shared
    }

    var isHebrew: Bool { localeIdentifier.hasPrefix("he") }
    var isChinese: Bool { localeIdentifier.hasPrefix("zh") }
}
