import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
struct NativeAppPasteboardBroker {
    let appID: String?
    let capabilityRegistry: NativeCapabilityRegistry

    // Central policy boundary for future capability and user-approval enforcement.
    func readString() -> String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        nil
        #endif
    }

    func writeString(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #endif
    }
}
