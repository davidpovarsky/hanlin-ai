#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Image {
    /// Original Hanlin images resolve from the SDK. Host-provided mini-app image
    /// names keep the original host-bundle lookup when the SDK does not own them.
    @MainActor
    init(hanlinAsset name: String) {
        let shared = HanlinLocalization.bundle
        #if canImport(UIKit)
        let owned = UIImage(named: name, in: shared, compatibleWith: nil) != nil
        #elseif canImport(AppKit)
        let owned = shared.image(forResource: NSImage.Name(name)) != nil
        #else
        let owned = true
        #endif
        self.init(name, bundle: owned ? shared : nil)
    }
}
#endif
