#if os(iOS)
import AVFoundation
import Foundation
import ImageIO
import Synchronization

nonisolated struct HanlinCameraPhotoBytes: Sendable {
    let data: Data
    let width: Int
    let height: Int
}

/// AVFoundation configuration and blocking start/stop are actor isolated, off
/// MainActor. No package runtime, shared container or network exists here.
actor HanlinCameraService {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var source: HanlinCameraPreviewSource?
    private var activeDelegate: HanlinCameraPhotoDelegate?
    private var capturing = false
    private var activityGeneration: UInt64 = 0
    private var desiredActive = false

    func start(generation: UInt64) async throws -> HanlinCameraPreviewSource {
        guard generation >= activityGeneration else { throw CancellationError() }
        activityGeneration = generation
        desiredActive = true
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = authorization == .authorized
        if authorization == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        // Authorization can suspend while stop or a newer start enters this actor.
        guard desiredActive, activityGeneration == generation, !Task.isCancelled else {
            throw CancellationError()
        }
        guard allowed else { throw HanlinCameraCaptureError.permissionDenied }
        if source == nil { try configure() }
        guard let source else { throw HanlinCameraCaptureError.cannotConfigureCamera }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else { throw HanlinCameraCaptureError.captureUnavailable }
        return source
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video) else { throw HanlinCameraCaptureError.cameraUnavailable }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw HanlinCameraCaptureError.cannotConfigureCamera
        }
        session.addInput(input)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        source = .init(session: session, device: device)
    }

    func stop(generation: UInt64) {
        guard generation >= activityGeneration else { return }
        activityGeneration = generation
        desiredActive = false
        if session.isRunning { session.stopRunning() }
    }

    func capture(rotationAngle: CGFloat) async throws -> HanlinCameraPhotoBytes {
        guard desiredActive, session.isRunning, !capturing, output.availablePhotoCodecTypes.contains(.jpeg) else {
            throw HanlinCameraCaptureError.captureUnavailable
        }
        capturing = true
        defer { capturing = false; activeDelegate = nil }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = HanlinCameraPhotoDelegate(continuation: continuation)
            activeDelegate = delegate
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            output.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

/// Delegate callbacks may arrive off the main actor. The standard-library mutex
/// owns all mutable callback state; no unchecked Sendable conformance is added.
nonisolated final class HanlinCameraPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private struct State {
        var continuation: CheckedContinuation<HanlinCameraPhotoBytes, any Error>?
        var result: Result<HanlinCameraPhotoBytes, any Error>?
    }
    private let state: Mutex<State>

    init(continuation: CheckedContinuation<HanlinCameraPhotoBytes, any Error>) {
        state = Mutex(State(continuation: continuation))
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let result: Result<HanlinCameraPhotoBytes, any Error>
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation(),
                let image = CGImageSourceCreateWithData(data as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                width > 0, height > 0 {
            result = .success(.init(data: data, width: width, height: height))
        } else { result = .failure(HanlinCameraCaptureError.invalidPhoto) }
        state.withLock { $0.result = result }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: (any Error)?) {
        let completion = state.withLock { value -> (CheckedContinuation<HanlinCameraPhotoBytes, any Error>?, Result<HanlinCameraPhotoBytes, any Error>) in
            let continuation = value.continuation
            value.continuation = nil
            let result: Result<HanlinCameraPhotoBytes, any Error> = error.map { .failure($0) }
                ?? value.result ?? .failure(HanlinCameraCaptureError.invalidPhoto)
            return (continuation, result)
        }
        completion.0?.resume(with: completion.1)
    }
}
#endif
