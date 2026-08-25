import Foundation
import UIKit

@MainActor
enum HanlinAppleDeviceSnapshotProvider {
    static func snapshot() -> HanlinScriptingDeviceSnapshot {
        let device = UIDevice.current
        let wasBatteryMonitoringEnabled = device.isBatteryMonitoringEnabled
        if !wasBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        defer {
            if !wasBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = false }
        }

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { activationRank($0.activationState) < activationRank($1.activationState) }
            .first
        let screen = scene?.screen
        let bounds = screen?.bounds ?? .zero
        let orientation = orientationName(scene?.interfaceOrientation)
        let locale = Locale.current
        let languageTag = Locale.preferredLanguages.first ?? locale.identifier

        return HanlinScriptingDeviceSnapshot(
            model: device.model,
            localizedModel: device.localizedModel,
            systemVersion: device.systemVersion,
            systemName: device.systemName,
            isiPad: device.userInterfaceIdiom == .pad,
            isiPhone: device.userInterfaceIdiom == .phone,
            screen: .init(
                width: bounds.width,
                height: bounds.height,
                scale: screen?.scale ?? 1
            ),
            batteryState: batteryStateName(device.batteryState),
            batteryLevel: Double(device.batteryLevel),
            proximityState: device.proximityState,
            orientation: orientation,
            colorScheme: scene?.traitCollection.userInterfaceStyle == .dark ? "dark" : "light",
            isiOSAppOnMac: ProcessInfo.processInfo.isiOSAppOnMac,
            systemLocale: locale.identifier,
            preferredLanguages: Locale.preferredLanguages,
            systemLanguageTag: languageTag,
            systemLanguageCode: locale.language.languageCode?.identifier ?? "und",
            systemCountryCode: locale.region?.identifier,
            systemScriptCode: locale.language.script?.identifier
        )
    }

    private static func activationRank(_ state: UIScene.ActivationState) -> Int {
        switch state {
        case .foregroundActive: 0
        case .foregroundInactive: 1
        case .background: 2
        case .unattached: 3
        @unknown default: 4
        }
    }

    private static func orientationName(_ orientation: UIInterfaceOrientation?) -> String {
        switch orientation {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        default: "unknown"
        }
    }

    private static func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .full: "full"
        case .charging: "charging"
        case .unplugged: "unplugged"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }
}
