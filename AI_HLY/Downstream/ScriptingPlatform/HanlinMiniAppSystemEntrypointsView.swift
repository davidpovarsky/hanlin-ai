import HanlinCameraCaptureUI
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptStore
import LockedCameraCapture
import SwiftUI

extension View {
    @MainActor
    func hanlinMiniAppSystemEntrypoints(platform: HanlinScriptingPlatform) -> some View {
        modifier(HanlinMiniAppSystemEntrypointsModifier(platform: platform))
    }
}

extension HanlinMiniAppSystemEntrypoints {
    /// A retained background window cannot own a newly requested foreground
    /// surface. Releasing a camera lease keeps its presentation and photos.
    func updateWindowActivity(_ active: Bool, windowID: UUID,
                              captures: HanlinMiniAppCaptureCoordinator) {
        if active {
            claimPresentation(windowID: windowID)
        } else {
            releasePresentation(windowID: windowID)
            captures.releaseWindow(windowID)
        }
    }
}

@MainActor
private struct HanlinMiniAppSystemEntrypointsModifier: ViewModifier {
    let platform: HanlinScriptingPlatform
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowID = UUID()
    @State private var windowIsActive = false
    @State private var captures = HanlinMiniAppCaptureCoordinator.shared
    @State private var systemEntrypoints = HanlinMiniAppSystemEntrypoints.shared
    @State private var cameraRequests = HanlinCameraCaptureRequests.shared

    func body(content: Content) -> some View {
        let shortcutID = platform.shortcutPresentation?.id
        content
            .task {
                windowIsActive = scenePhase == .active
                await platform.restore()
                await captures.start()
                await admit()
            }
            .onContinueUserActivity(NSUserActivityTypeLockedCameraCapture) { _ in
                Task { await captures.start(); await admit(); await captures.processAvailable() }
            }
            .onChange(of: cameraRequests.pendingRequestID) { _, _ in Task { await admit() } }
            .onChange(of: captures.showsInbox) { _, _ in Task { await admit() } }
            .onChange(of: captures.cameraWindowID) { _, _ in Task { await admit() } }
            .onChange(of: captures.cameraContextLoading) { _, loading in
                if !loading { Task { await admit() } }
            }
            .onChange(of: captures.cameraPresentation?.id) { old, current in
                // When a package was already presented, camera and package share
                // one cover. A finished capture switches its content in place.
                Task {
                    if old != nil, current == nil, platform.isForegroundPresentationVisible {
                        await captures.cameraDidDismiss(windowID: windowID)
                    }
                    // A camera request may finish loading after its former
                    // window became inactive. Another active scene can claim it.
                    await admit()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                windowIsActive = phase == .active
                if phase == .active {
                    Task { await admit(); await captures.processAvailable() }
                } else {
                    systemEntrypoints.updateWindowActivity(false, windowID: windowID, captures: captures)
                }
            }
            .onChange(of: systemEntrypoints.presentationWindowID) { _, _ in Task { await admit() } }
            .onDisappear {
                windowIsActive = false
                systemEntrypoints.updateWindowActivity(false, windowID: windowID, captures: captures)
            }
            .fullScreenCover(isPresented: Binding(
                get: { (captures.cameraWindowID == windowID && captures.cameraPresentation != nil) || (platform.isForegroundPresentationVisible && systemEntrypoints.presentationWindowID == windowID) },
                set: {
                    if !$0, systemEntrypoints.presentationWindowID == windowID {
                        if let shortcutID { platform.dismissShortcutPresentation(shortcutID) }
                        else { platform.dismissActiveApplication() }
                    }
                }
            ), onDismiss: { Task { await captures.cameraDidDismiss(windowID: windowID); await admit() } }) {
                if captures.cameraWindowID == windowID, let presentation = captures.cameraPresentation {
                    HanlinCameraCaptureView(directory: presentation.directory,
                        productIdentifier: HanlinMiniAppSystemEntrypoints.productIdentifier,
                        source: .applicationCamera, target: presentation.target,
                        finish: { directory in try await captures.finishApplicationCapture(directory: directory) },
                        cancel: { captures.cancelApplicationCapture(directory: presentation.directory) })
                        .interactiveDismissDisabled()
                } else {
                    ScriptingApplicationContainerView(platform: platform.foregroundPresentationPlatform,
                        onClose: {
                            if let shortcutID { platform.dismissShortcutPresentation(shortcutID) }
                            else { platform.dismissActiveApplication() }
                        })
                }
            }
            .sheet(isPresented: Binding(
                get: { captures.showsInbox && captures.inboxWindowID == windowID },
                set: { if !$0 { captures.showsInbox = false } }
            ), onDismiss: { Task { await captures.inboxDidDismiss(windowID: windowID) } }) {
                NavigationStack { HanlinMiniAppCaptureDeliveriesView() }
            }
            .alert("Capture unavailable", isPresented: Binding(
                get: { captures.error != nil && !captures.showsInbox && captures.cameraPresentation == nil },
                set: { if !$0 { captures.error = nil } }
            )) { Button("OK") { captures.error = nil } }
                message: { Text(captures.error ?? "") }
    }

    private func admit() async {
        guard windowIsActive else { return }
        systemEntrypoints.updateWindowActivity(true, windowID: windowID, captures: captures)
        await captures.claimCameraRequest(windowID: windowID)
        // Loading the system camera context suspends. A scene can lose its
        // foreground state while that request is in flight.
        guard windowIsActive else {
            systemEntrypoints.updateWindowActivity(false, windowID: windowID, captures: captures)
            return
        }
        captures.claimInbox(windowID: windowID)
    }
}

@MainActor
struct HanlinMiniAppCaptureSection: View {
    let package: HanlinStoredPackageSnapshot
    let platform: HanlinScriptingPlatform
    @State private var captures = HanlinMiniAppCaptureCoordinator.shared

    private var records: [HanlinMiniAppSystemRecord] {
        HanlinMiniAppSystemEntrypoints.shared.captureRecords.filter {
            $0.installedPackageID == package.record.installedPackageID
        }
    }

    var body: some View {
        if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct, !records.isEmpty {
            Section("Camera") {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.entrypoint.id).font(.headline)
                        if captures.selectedTarget == record.cameraTarget {
                            Label("Selected for Camera Control", systemImage: "checkmark.circle")
                        } else {
                            Button("Use for Camera Control") {
                                Task {
                                    do { try await captures.select(record) }
                                    catch { captures.error = error.localizedDescription }
                                }
                            }.accessibilityIdentifier("miniapp-camera-select-" + record.entrypoint.id)
                        }
                        Button("Open camera") { Task { await captures.requestCamera(for: record) } }
                            .accessibilityIdentifier("miniapp-camera-open-" + record.entrypoint.id)
                    }
                }
                Button("Captured photos and delivery status") { captures.showsInbox = true }
                    .accessibilityIdentifier("miniapp-camera-deliveries")
            }
        }
        if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct,
           package.entrypoints.contains(where: { $0.kind == .spotlight }),
           let error = HanlinMiniAppSystemEntrypoints.shared.spotlightError {
            Section("Spotlight") { Text(error).foregroundStyle(.secondary) }
        }
    }
}

@MainActor
private struct HanlinMiniAppCaptureDeliveriesView: View {
    @State private var captures = HanlinMiniAppCaptureCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let error = captures.error {
                Section { Text(error).foregroundStyle(.secondary) }
            }
            if captures.deliveries.isEmpty {
                ContentUnavailableView("No captured photos", systemImage: "camera")
            }
            ForEach(captures.deliveries) { delivery in
                Section {
                    Text("\(delivery.manifest.photos.count) photos")
                    if let receipt = captures.receipts[delivery.id] {
                        LabeledContent("Delivery", value: receipt.status.rawValue)
                            .accessibilityIdentifier("miniapp-camera-delivery-" + delivery.id.uuidString.lowercased())
                        if let failure = receipt.failure { Text(failure.rawValue).foregroundStyle(.secondary) }
                    }
                    if captures.receipts[delivery.id] == nil || captures.receipts[delivery.id]?.status == .stale {
                        ForEach(HanlinMiniAppSystemEntrypoints.shared.captureRecords) { record in
                            Button("Continue with \(record.title) — \(record.entrypoint.id)") {
                                Task { await captures.choose(record, for: delivery) }
                            }
                        }
                        if HanlinMiniAppSystemEntrypoints.shared.captureRecords.isEmpty {
                            Text("Install or enable a package with a camera capture action to continue. Your photos remain saved in this app.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Captured photos")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await captures.reload() }
        .refreshable { await captures.reload() }
    }
}
