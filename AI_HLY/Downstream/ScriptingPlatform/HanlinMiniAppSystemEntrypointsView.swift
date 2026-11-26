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

@MainActor
private struct HanlinMiniAppSystemEntrypointsModifier: ViewModifier {
    let platform: HanlinScriptingPlatform
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowID = UUID()
    @State private var captures = HanlinMiniAppCaptureCoordinator.shared
    @State private var systemEntrypoints = HanlinMiniAppSystemEntrypoints.shared
    @State private var cameraRequests = HanlinCameraCaptureRequests.shared

    func body(content: Content) -> some View {
        content
            .task {
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
            .onChange(of: captures.cameraPresentation?.id) { old, current in
                // When a package was already presented, camera and package share
                // one cover. A finished capture switches its content in place.
                if old != nil, current == nil, platform.presentsForegroundAction {
                    Task { await captures.cameraDidDismiss(); await admit() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await admit(); await captures.processAvailable() } }
            }
            .onChange(of: systemEntrypoints.presentationWindowID) { _, _ in Task { await admit() } }
            .onDisappear {
                captures.releaseWindow(windowID)
                systemEntrypoints.releasePresentation(windowID: windowID)
            }
            .fullScreenCover(isPresented: Binding(
                get: { (captures.cameraWindowID == windowID && captures.cameraPresentation != nil) || (platform.presentsForegroundAction && systemEntrypoints.presentationWindowID == windowID) },
                set: { if !$0 { platform.dismissActiveApplication() } }
            ), onDismiss: { Task { await captures.cameraDidDismiss(); await admit() } }) {
                if captures.cameraWindowID == windowID, let presentation = captures.cameraPresentation {
                    HanlinCameraCaptureView(directory: presentation.directory,
                        productIdentifier: HanlinMiniAppSystemEntrypoints.productIdentifier,
                        source: .applicationCamera, target: presentation.target,
                        finish: { directory in try await captures.finishApplicationCapture(directory: directory) },
                        cancel: { captures.cancelApplicationCapture(directory: presentation.directory) })
                        .interactiveDismissDisabled()
                } else {
                    ScriptingApplicationContainerView(platform: platform)
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
        guard scenePhase == .active else { return }
        systemEntrypoints.claimPresentation(windowID: windowID)
        await captures.claimCameraRequest(windowID: windowID)
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
        if !records.isEmpty {
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
        if package.entrypoints.contains(where: { $0.kind == .spotlight }),
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
