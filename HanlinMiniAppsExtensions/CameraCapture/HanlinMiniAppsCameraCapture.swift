import AppIntents
import HanlinCameraCaptureUI
import LockedCameraCapture
import SwiftUI

@main
struct HanlinMiniAppsCameraCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            HanlinLockedCameraCaptureView(session: session)
        }
    }
}

struct HanlinMiniAppsCameraCaptureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [HanlinCameraCaptureIntentsPackage.self] }
}
