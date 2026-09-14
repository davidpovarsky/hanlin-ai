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
    static let title: LocalizedStringResource = "Enable ChavrusaChat Notifications"
    static let description = IntentDescription("Enables reminders, time-sensitive updates, and remote notifications for ChavrusaChat.")
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
    static let title: LocalizedStringResource = "Schedule a ChavrusaChat Alarm"
    static let description = IntentDescription("Schedules a prominent study alarm using the system alarm service.")
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
        let alert = AlarmPresentation.Alert(
            title: "ChavrusaChat Alarm",
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
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
            phrases: ["Schedule a study alarm in \(.applicationName)"],
            shortTitle: "Study Alarm",
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
