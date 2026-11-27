import HanlinWidgetUI
import HanlinLocalization
import AlarmKit
import AppIntents
import Foundation
import UIKit
import UserNotifications

enum ChavrusaSystemIntegrationBootstrap {
    static func configure() async {
        guard let identifier = HanlinApplicationProcessRuntime.shared.systemIntegrations.notificationCategoryIdentifier,
              !identifier.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
        let merged = categories(existing, adding: identifier)
        // Apple's setter replaces the complete set. Retain every host category
        // and any host-defined actions on an already registered same identifier.
        if merged.count != existing.count { center.setNotificationCategories(merged) }
    }

    static func categories(_ existing: Set<UNNotificationCategory>, adding identifier: String)
        -> Set<UNNotificationCategory> {
        guard !identifier.isEmpty, !existing.contains(where: { $0.identifier == identifier }) else {
            return existing
        }
        var merged = existing
        merged.insert(UNNotificationCategory(identifier: identifier, actions: [],
            intentIdentifiers: [], options: [.customDismissAction]))
        return merged
    }
}

public struct EnableChavrusaNotificationsIntent: AppIntent {
    public static let title = LocalizedStringResource("Enable Hanlin Notifications", table: "HanlinAppIntents")
    public static let description = IntentDescription(LocalizedStringResource("Enables notifications for Hanlin after you grant system permission.", table: "HanlinAppIntents"))
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .timeSensitive])
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            return .result(dialog: IntentDialog(LocalizedStringResource("Notifications are enabled.", bundle: .atURL(HanlinLocalization.bundle.bundleURL))))
        }
        return .result(dialog: IntentDialog(LocalizedStringResource("Notification permission wasn’t granted. You can enable it in Settings.", bundle: .atURL(HanlinLocalization.bundle.bundleURL))))
    }
}

struct ChavrusaAlarmMetadata: AlarmMetadata {
    let note: String
}

public struct ScheduleChavrusaAlarmIntent: AppIntent {
    public static let title = LocalizedStringResource("Schedule an Alarm with Hanlin", table: "HanlinAppIntents")
    public static let description = IntentDescription(LocalizedStringResource("Schedules a system alarm at the time you choose.", table: "HanlinAppIntents"))
    public static let openAppWhenRun = false

    @Parameter(title: LocalizedStringResource("Hour", table: "HanlinAppIntents"), inclusiveRange: (0, 23))
    public var hour: Int

    @Parameter(title: LocalizedStringResource("Minute", table: "HanlinAppIntents"), inclusiveRange: (0, 59))
    public var minute: Int

    @Parameter(title: LocalizedStringResource("Title", table: "HanlinAppIntents"))
    public var alarmTitle: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let authorization = try await AlarmManager.shared.requestAuthorization()
        guard authorization == .authorized else {
            return .result(dialog: IntentDialog(LocalizedStringResource("Alarm access wasn’t granted.", bundle: .atURL(HanlinLocalization.bundle.bundleURL))))
        }

        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let schedule: Alarm.Schedule = .relative(.init(time: time, repeats: .never))
        let enteredTitle = alarmTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = enteredTitle.isEmpty ? String(localized: "Alarm", bundle: HanlinLocalization.bundle) : enteredTitle
        let alert = AlarmPresentation.Alert(title: "\(displayTitle)")
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: ChavrusaAlarmMetadata(note: alarmTitle),
            tintColor: .blue
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes
        )
        try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
        return .result(dialog: IntentDialog(LocalizedStringResource("The alarm was scheduled.", bundle: .atURL(HanlinLocalization.bundle.bundleURL))))
    }
}

public struct ChavrusaChatShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScheduleChavrusaAlarmIntent(),
            phrases: ["Schedule an alarm in \(.applicationName)"],
            shortTitle: LocalizedStringResource("Schedule Alarm", table: "HanlinAppIntents"),
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: EnableChavrusaNotificationsIntent(),
            phrases: ["Enable notifications in \(.applicationName)"],
            shortTitle: LocalizedStringResource("Enable Notifications", table: "HanlinAppIntents"),
            systemImageName: "bell.badge"
        )
    }
}

/// Include this type from the host app's `AppIntentsPackage.includedPackages`
/// to index the original Hanlin intent implementations after SDK extraction.
public struct HanlinApplicationIntentsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinWidgetIntentsPackage.self]
    }
}
