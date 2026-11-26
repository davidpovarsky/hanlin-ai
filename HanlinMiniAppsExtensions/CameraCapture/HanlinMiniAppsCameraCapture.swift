import AppIntents
import ExtensionKit
import HanlinCameraCaptureUI
import LockedCameraCapture
import SwiftUI

@main
struct HanlinMiniAppsCameraCaptureExtension: @MainActor LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            HanlinLockedCameraCaptureView(session: session)
        }
    }
}

struct HanlinMiniAppsCameraCaptureIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [HanlinCameraCaptureIntentsPackage.self] }
}
