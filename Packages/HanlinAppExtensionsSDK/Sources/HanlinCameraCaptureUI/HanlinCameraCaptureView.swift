#if os(iOS)
import AVFoundation
import AVKit
import Foundation
import LockedCameraCapture
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
private final class HanlinCameraViewModel {
    var source: HanlinCameraPreviewSource?
    var ready = false
    var capturing = false
    var photoCount = 0
    var error: String?
    var rotationAngle: CGFloat = 90
    private let service = HanlinCameraService()
    private var files: HanlinCameraSessionFiles?
    private var activityGeneration: UInt64 = 0

    func start(directory: URL, productIdentifier: String, captureSource: HanlinCameraCaptureSource,
               target: HanlinCameraCaptureTarget?) async {
        activityGeneration += 1
        let generation = activityGeneration
        do {
            if files == nil {
                files = try HanlinCameraSessionFiles(directory: directory, productIdentifier: productIdentifier,
                    source: captureSource, target: target)
            }
            if let files { photoCount = await files.currentManifest().photos.count }
            guard activityGeneration == generation, !Task.isCancelled else { return }
            let preview = try await service.start(generation: generation)
            guard activityGeneration == generation, !Task.isCancelled else { return }
            source = preview
            ready = true; error = nil
        } catch {
            guard activityGeneration == generation else { return }
            ready = false
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    func capture() async {
        guard ready, !capturing, let files else { return }
        capturing = true
        defer { capturing = false }
        do {
            let photo = try await service.capture(rotationAngle: rotationAngle)
            _ = try await files.saveJPEG(photo.data, width: photo.width, height: photo.height)
            photoCount = await files.currentManifest().photos.count
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func stop() -> Task<Void, Never> {
        // Invalidate synchronously on MainActor before scheduling actor work.
        activityGeneration += 1
        let generation = activityGeneration
        ready = false
        return Task { await service.stop(generation: generation) }
    }
}

@MainActor
public struct HanlinCameraCaptureView: View {
    private let directory: URL
    private let productIdentifier: String
    private let captureSource: HanlinCameraCaptureSource
    private let target: HanlinCameraCaptureTarget?
    private let finish: @MainActor (URL) async throws -> Void
    private let cancel: @MainActor () async throws -> Void
    @State private var model = HanlinCameraViewModel()
    @State private var finishing = false
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase

    public init(directory: URL, productIdentifier: String, source: HanlinCameraCaptureSource,
                target: HanlinCameraCaptureTarget?,
                finish: @escaping @MainActor (URL) async throws -> Void,
                cancel: @escaping @MainActor () async throws -> Void) {
        self.directory = directory; self.productIdentifier = productIdentifier
        self.captureSource = source; self.target = target; self.finish = finish; self.cancel = cancel
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let source = model.source {
                HanlinCameraPreview(source: source, enabled: model.ready && !model.capturing && !finishing,
                    capture: { Task { await model.capture() } },
                    rotation: { model.rotationAngle = $0 })
                    .ignoresSafeArea()
                    .accessibilityIdentifier("miniapp-camera-preview")
            }
            VStack {
                HStack {
                    Button("Cancel", role: .cancel) {
                        Task {
                            do { await model.stop().value; try await cancel() }
                            catch { model.error = error.localizedDescription }
                        }
                    }.disabled(model.capturing || finishing)
                    Spacer()
                    Text("\(model.photoCount) photos").accessibilityIdentifier("miniapp-camera-photo-count")
                }
                .padding().background(.ultraThinMaterial)
                Spacer()
                if let error = model.error {
                    VStack {
                        Text(error).multilineTextAlignment(.center)
                        if !model.ready { Button("Try camera again") { Task { await start() } } }
                    }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding().accessibilityIdentifier("miniapp-camera-error")
                }
                HStack(spacing: 28) {
                    Button { Task { await model.capture() } } label: {
                        Image(systemName: "camera.circle.fill").font(.system(size: 68))
                    }
                    .accessibilityLabel("Take photo").accessibilityIdentifier("miniapp-camera-shutter")
                    .disabled(!model.ready || model.capturing || finishing)
                    Button("Continue in app") {
                        finishing = true
                        Task {
                            do {
                                // Keep the live capture session until the OS accepts
                                // handoff; cancelling authentication leaves a usable camera.
                                try await finish(directory)
                            } catch { model.error = error.localizedDescription }
                            finishing = false
                        }
                    }
                    .disabled(model.photoCount == 0 || model.capturing || finishing)
                    .accessibilityIdentifier("miniapp-camera-continue")
                }.padding().background(.ultraThinMaterial)
            }
        }
        .onAppear { visible = true }
        .task { await start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await start() } } else { model.stop() }
        }
        .onDisappear { visible = false; model.stop() }
    }

    private func start() async {
        guard visible, scenePhase == .active else { return }
        await model.start(directory: directory, productIdentifier: productIdentifier, captureSource: captureSource, target: target)
    }
}

@MainActor
struct HanlinCameraPreview: UIViewRepresentable {
    let source: HanlinCameraPreviewSource
    let enabled: Bool
    let capture: @MainActor () -> Void
    let rotation: @MainActor (CGFloat) -> Void

    func makeUIView(context: Context) -> HanlinCameraPreviewView {
        let view = HanlinCameraPreviewView()
        view.capture = capture; view.rotation = rotation
        source.connect(to: view)
        view.interaction.isEnabled = enabled
        return view
    }

    func updateUIView(_ view: HanlinCameraPreviewView, context: Context) {
        view.capture = capture; view.rotation = rotation
        view.interaction.isEnabled = enabled
    }

    static func dismantleUIView(_ view: HanlinCameraPreviewView, coordinator: Void) {
        view.interaction.isEnabled = false
        view.previewLayer.session = nil
    }
}

@MainActor
final class HanlinCameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var capture: (@MainActor () -> Void)?
    var rotation: (@MainActor (CGFloat) -> Void)?
    var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewObservation: NSKeyValueObservation?
    private var captureObservation: NSKeyValueObservation?
    lazy var interaction: AVCaptureEventInteraction = AVCaptureEventInteraction { [weak self] event in
        guard event.phase == .ended else { return }
        Task { @MainActor [weak self] in self?.capture?() }
    }

    init() {
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        interaction.isEnabled = false
        addInteraction(interaction)
    }
    required init?(coder: NSCoder) { return nil }

    func observeRotation() {
        previewObservation = rotationCoordinator?.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateRotation() }
        }
        captureObservation = rotationCoordinator?.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateRotation() }
        }
    }

    private func updateRotation() {
        guard let coordinator = rotationCoordinator else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        rotation?(coordinator.videoRotationAngleForHorizonLevelCapture)
    }
}

@MainActor
public struct HanlinLockedCameraCaptureView: View {
    private let session: LockedCameraCaptureSession
    @State private var target: HanlinCameraCaptureTarget?
    @State private var loaded = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(session: LockedCameraCaptureSession) { self.session = session }

    public var body: some View {
        Group {
            if let product = Bundle.main.object(forInfoDictionaryKey: "HanlinContainingApplicationIdentifier") as? String {
                if loaded {
                    HanlinCameraCaptureView(directory: session.sessionContentURL, productIdentifier: product,
                        source: .lockedCamera, target: target,
                        finish: { _ in
                            let activity = NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)
                            activity.title = "Continue captured photos"
                            // The receiving app reads only Manager-provided directories.
                            // No extension URL is conveyed as executable authority.
                            try await session.openApplication(for: activity)
                        }, cancel: {
                            try await session.invalidateSessionContent()
                            dismiss()
                        })
                } else { ProgressView().task { await load(product: product) } }
            } else {
                ContentUnavailableView("Camera unavailable", systemImage: "camera", description: Text("The containing application could not be identified."))
            }
        }
        .alert("Camera context unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func load(product: String) async {
        do {
            let context = try await HanlinCameraCaptureIntent.appContext
            target = context?.productIdentifier == product ? context : nil
        } catch { self.error = error.localizedDescription }
        loaded = true // No selection is valid: capture now, choose a package in the app.
    }
}
#endif
