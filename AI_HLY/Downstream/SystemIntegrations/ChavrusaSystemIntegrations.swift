import AlarmKit
import AppIntents
import Foundation
import UIKit
import UserNotifications

enum ChavrusaSystemIntegrationBootstrap {
    static func configure() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: "CHAVRUSA_REMINDER",
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
    }
}

struct EnableChavrusaNotificationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Enable Hanlin Notifications"
    static let description = IntentDescription("Enables notifications for Hanlin after you grant system permission.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .timeSensitive])
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            return .result(dialog: "Notifications are enabled.")
        }
        return .result(dialog: "Notification permission wasn’t granted. You can enable it in Settings.")
    }
}

struct ChavrusaAlarmMetadata: AlarmMetadata {
    let note: String
}

struct ScheduleChavrusaAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Schedule an Alarm with Hanlin"
    static let description = IntentDescription("Schedules a system alarm at the time you choose.")
    static let openAppWhenRun = false

    @Parameter(title: "Hour", inclusiveRange: (0, 23))
    var hour: Int

    @Parameter(title: "Minute", inclusiveRange: (0, 59))
    var minute: Int

    @Parameter(title: "Title")
    var alarmTitle: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let authorization = try await AlarmManager.shared.requestAuthorization()
        guard authorization == .authorized else {
            return .result(dialog: "Alarm access wasn’t granted.")
        }

        let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let schedule: Alarm.Schedule = .relative(.init(time: time, repeats: .never))
        let enteredTitle = alarmTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = enteredTitle.isEmpty ? String(localized: "Alarm") : enteredTitle
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
        return .result(dialog: "The alarm was scheduled.")
    }
}

struct ChavrusaChatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScheduleChavrusaAlarmIntent(),
            phrases: ["Schedule an alarm in \(.applicationName)"],
            shortTitle: "Schedule Alarm",
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: EnableChavrusaNotificationsIntent(),
            phrases: ["Enable notifications in \(.applicationName)"],
            shortTitle: "Enable Notifications",
            systemImageName: "bell.badge"
        )
    }
}
