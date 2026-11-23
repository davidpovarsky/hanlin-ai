import Foundation

/// Original resources travel with the shared implementation in every host.
public enum HanlinApplicationResources {
    public static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }()
}
