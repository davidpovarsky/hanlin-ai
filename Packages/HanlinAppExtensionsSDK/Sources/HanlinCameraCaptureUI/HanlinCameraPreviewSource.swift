#if os(iOS)
// AVFoundation's Objective-C capture session is not annotated Sendable. This
// narrowly scoped immutable preview binding follows Apple's current AVCam
// PreviewSource pattern. All mutable session work stays on HanlinCameraService;
// only attachment to the UI preview layer happens on MainActor.
@preconcurrency import AVFoundation
import UIKit

nonisolated struct HanlinCameraPreviewSource: Sendable {
    private let session: AVCaptureSession
    private let device: AVCaptureDevice

    init(session: AVCaptureSession, device: AVCaptureDevice) {
        self.session = session; self.device = device
    }

    @MainActor
    func connect(to view: HanlinCameraPreviewView) {
        view.previewLayer.session = session
        view.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.previewLayer)
        view.observeRotation()
    }
}
#endif
