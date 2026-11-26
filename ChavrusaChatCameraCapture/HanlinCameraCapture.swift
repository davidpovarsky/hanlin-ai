import AppIntents
import ExtensionKit
import HanlinCameraCaptureUI
import LockedCameraCapture
import SwiftUI

@main
struct HanlinCameraCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            HanlinLockedCameraCaptureView(session: session)
        }
    }
}

struct HanlinCameraCaptureExtensionIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [HanlinCameraCaptureIntentsPackage.self] }
}
