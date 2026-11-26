#if os(iOS)
import AppIntents
import Foundation
import Observation
import SwiftUI
import WidgetKit

/// Included in the containing app, its Control widget, and its capture extension.
/// CameraCaptureIntent lets the OS choose locked-extension or foreground launch.
public struct HanlinCameraCaptureIntent: CameraCaptureIntent {
    public typealias AppContext = HanlinCameraCaptureTarget
    public static let title: LocalizedStringResource = "Capture with a mini app"
    public static let description = IntentDescription("Capture photos, then continue in your selected installed mini app.")
    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        HanlinCameraCaptureRequests.shared.request()
        return .result()
    }
}

@MainActor
@Observable
public final class HanlinCameraCaptureRequests {
    public static let shared = HanlinCameraCaptureRequests()
    public private(set) var pendingRequestID: UUID?
    private init() {}
    public func request() { pendingRequestID = UUID() }
    public func consume() -> Bool {
        guard pendingRequestID != nil else { return false }
        pendingRequestID = nil
        return true
    }
}

public struct HanlinCameraCaptureControl: ControlWidget {
    public static let kind = "com.hanlin.miniapp.camera-capture"
    public init() {}
    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: HanlinCameraCaptureIntent()) {
                Label("Capture", systemImage: "camera")
            }
        }
        .displayName("Capture with a mini app")
        .description("Open the camera and send captured photos to your selected installed mini app.")
    }
}

public struct HanlinCameraCaptureIntentsPackage: AppIntentsPackage {}
#endif
