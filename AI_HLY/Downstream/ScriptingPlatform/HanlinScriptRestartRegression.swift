import Foundation
import HanlinScriptContracts
import HanlinScriptStore
import Observation
import SwiftUI

/// Simulator-only evidence harness selected by an explicit CI environment variable.
/// Production launches do not create or execute this modifier's driver.
struct HanlinScriptRestartRegressionModifier: ViewModifier {
    @State private var controller = HanlinScriptRestartRegressionController.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if controller.isActive {
                    Text(controller.status)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
                        .padding(24)
                        .accessibilityIdentifier("script-restart-repro-status")
                }
            }
    }
}

@MainActor
@Observable
final class HanlinScriptRestartRegressionController {
    static let shared = HanlinScriptRestartRegressionController()

    var status = "Preparing Script App restart reproduction"
    private(set) var isActive = false
    @ObservationIgnored private var driverTask: Task<Void, Never>?
    @ObservationIgnored private var activePhase: String?

    private init() {}

    func startFromEnvironment() {
        start(phase: ProcessInfo.processInfo.environment["HANLIN_SCRIPT_RESTART_REPRO_PHASE"])
    }

    private func start(phase: String?) {
        guard let phase, phase != activePhase else { return }
        driverTask?.cancel()
        activePhase = phase
        isActive = true
        // The external CI process owns the checkpoint lifecycle. Keeping this
        // task in the controller prevents an overlay re-render from cancelling
        // the driver between two process-boundary checkpoints.
        driverTask = Task { [weak self] in
            guard let self else { return }
            let driver = HanlinScriptRestartRegressionDriver()
            await driver.run(phase: phase) { [weak self] value in self?.status = value }
        }
    }

}

@MainActor
private struct HanlinScriptRestartRegressionDriver {
    private let platform = HanlinScriptingPlatform.shared
    private let manager = FileManager.default

    func run(phase: String, updateStatus: @escaping @MainActor (String) -> Void) async {
        do {
            switch phase {
            case "install":
                try await runInstallPhase(updateStatus: updateStatus)
            case "restore":
                try await runRestorePhase(updateStatus: updateStatus)
            default:
                throw RegressionError.invalidPhase(phase)
            }
        } catch {
            updateStatus("Reproduction harness failed: \(String(describing: error))")
            try? checkpoint("harness-failed", error: error)
        }
    }

    private func runInstallPhase(
        updateStatus: @escaping @MainActor (String) -> Void
    ) async throws {
        await platform.restore()
        updateStatus("01 · Clean Apps screen · no imported package")
        try await checkpointAndWait("01-clean-apps-screen")

        guard let fixturePath = ProcessInfo.processInfo.environment["HANLIN_SCRIPT_RESTART_REPRO_FIXTURE"] else {
            throw RegressionError.fixtureMissing
        }
        let fixture = URL(filePath: fixturePath, directoryHint: .notDirectory)
        updateStatus("02/03 · Import flow · system picker replaced by CI fixture injection")
        try await checkpointAndWait("02-import-flow-open")

        await platform.importPackage(from: fixture)
        guard let preview = platform.preview else {
            throw RegressionError.operationFailed(activityDescription)
        }
        updateStatus("04 · Exact normalized ZIP imported and previewed")
        try await checkpointAndWait("04-import-completed")
        try manager.removeItem(at: fixture)

        for capability in preview.requestedCapabilities.map(\.capabilityID) {
            platform.setCapabilityApproved(true, capability: capability)
        }
        await platform.installPreview()
        guard platform.activity == .idle, let installed = platform.installedPackages.first else {
            updateStatus("05 · Install result · no registered app · \(activityDescription)")
            try await checkpointAndWait("05-imported-app-visible")
            updateStatus("06 · First launch unavailable · \(activityDescription)")
            try await checkpointAndWait("06-first-launch-result")
            platform.clearFailure()
            updateStatus("07 · Install/launch error dismissed · ready for host termination")
            try await checkpointAndWait("07-before-process-termination")
            return
        }
        updateStatus("05 · Imported Script App visible · generation \(installed.record.activeGeneration)")
        try await checkpointAndWait("05-imported-app-visible")

        await platform.launch(installed.record.installedPackageID)
        updateStatus("06 · First launch result · \(activityDescription)")
        try await checkpointAndWait("06-first-launch-result")
        platform.clearFailure()
        updateStatus("07 · First-launch result dismissed · ready for host termination")
        try await checkpointAndWait("07-before-process-termination")
    }

    private func runRestorePhase(
        updateStatus: @escaping @MainActor (String) -> Void
    ) async throws {
        await platform.restore()
        updateStatus("08 · New host process · persisted Script App registry restored")
        try await checkpointAndWait("08-after-process-relaunch-apps-screen")
        guard let installed = platform.installedPackages.first else {
            updateStatus("09 · Second launch unavailable · restored registry contains no Script App")
            try await checkpointAndWait("09-second-launch-result")
            return
        }
        await platform.launch(installed.record.installedPackageID)
        updateStatus("09 · Second launch result · \(activityDescription)")
        try await checkpointAndWait("09-second-launch-result")
    }

    private var activityDescription: String {
        switch platform.activity {
        case .idle: "idle"
        case .importing: "importing"
        case .previewReady: "previewReady"
        case .installing: "installing"
        case .failed(let message): message
        }
    }

    private func checkpointAndWait(_ name: String) async throws {
        try checkpoint(name)
        let continuation = try evidenceRoot.appending(
            path: "continue-\(name)",
            directoryHint: .notDirectory
        )
        while !manager.fileExists(atPath: continuation.path()) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private func checkpoint(_ name: String, error: Error? = nil) throws {
        let root = try evidenceRoot
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let packages = try JSONEncoder.regression.encode(platform.installedPackages)
        let packageObjects = try JSONSerialization.jsonObject(with: packages)
        var payload: [String: Any] = [
            "schemaVersion": 1,
            "checkpoint": name,
            "processIdentifier": ProcessInfo.processInfo.processIdentifier,
            "activity": activityDescription,
            "fixtureSHA256": "c8ee66e4e5e6a06a884b2a1d7b552d51691cb824f245e4cca238bc44d1509d57",
            "applicationSupportRoot": try applicationSupport.path(percentEncoded: false),
            "standardizedApplicationSupportRoot": try applicationSupport.standardizedFileURL.path(percentEncoded: false),
            "symlinkResolvedApplicationSupportRoot": try applicationSupport.resolvingSymlinksInPath().path(percentEncoded: false),
            "packages": packageObjects,
        ]
        if let error { payload["error"] = String(describing: error) }
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: root.appending(path: "\(name).json"), options: .atomic)
        try Data().write(to: root.appending(path: "\(name).ready"), options: .atomic)
    }

    private var applicationSupport: URL {
        get throws {
            guard let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw RegressionError.applicationSupportMissing
            }
            return root
        }
    }

    private var evidenceRoot: URL {
        get throws {
            try applicationSupport.appending(
                path: "Hanlin/ScriptAppNodeRestartRepro",
                directoryHint: .isDirectory
            )
        }
    }

    private enum RegressionError: Error {
        case applicationSupportMissing
        case fixtureMissing
        case invalidPhase(String)
        case operationFailed(String)
    }
}

private extension JSONEncoder {
    static var regression: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}
