import Foundation
import SwiftData
import SwiftUI

typealias NativeOpenURLAction = @MainActor (URL) -> Void

struct NativeAppContext {
    var localeIdentifier: String
    var modelContext: ModelContext?
    var openURL: NativeOpenURLAction?
    var capabilityRegistry: NativeCapabilityRegistry

    init(
        localeIdentifier: String = Locale.current.identifier,
        modelContext: ModelContext? = nil,
        openURL: NativeOpenURLAction? = nil,
        capabilityRegistry: NativeCapabilityRegistry = .shared
    ) {
        self.localeIdentifier = localeIdentifier
        self.modelContext = modelContext
        self.openURL = openURL
        self.capabilityRegistry = capabilityRegistry
    }

    var isHebrew: Bool { localeIdentifier.hasPrefix("he") }
    var isChinese: Bool { localeIdentifier.hasPrefix("zh") }
}
