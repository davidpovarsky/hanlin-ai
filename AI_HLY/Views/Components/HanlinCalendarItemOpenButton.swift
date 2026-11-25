import EventKit
import EventKitUI
import HanlinLocalization
import HanlinScriptDeviceServices
import SwiftUI

/// Opens the saved record, never a title-based substitute or a generic Calendar
/// URL presented as an item-specific link. Apple supplies an exact event viewer;
/// reminders use a native detail form populated by a fresh EventKit ID lookup.
@MainActor
struct HanlinCalendarItemOpenButton: View {
    let item: EventItem
    @State private var selected: Selection?

    private struct Selection: Identifiable {
        let id = UUID()
        let item: EventItem
    }

    var body: some View {
        Button {
            selected = Selection(item: item)
        } label: {
            Label {
                Text("Open", bundle: HanlinLocalization.bundle)
            } icon: {
                Image(systemName: "arrow.up.forward.square")
            }
        }
        .accessibilityIdentifier("hanlin-calendar-open-item")
        .sheet(item: $selected) { selection in
            HanlinSavedCalendarItemSheet(item: selection.item)
        }
    }
}

@MainActor
private struct HanlinSavedCalendarItemSheet: View {
    let item: EventItem
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case event(EKEvent)
        case reminder(HanlinScriptReminderItem)
        case unavailable(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView {
                        Text("Loading item…", bundle: HanlinLocalization.bundle)
                    }
                case .event(let event):
                    EventDetails(event: event)
                case .reminder(let reminder):
                    Form {
                        Section {
                            LabeledContent {
                                Text(reminder.title)
                            } label: {
                                Text("Title", bundle: HanlinLocalization.bundle)
                            }
                            LabeledContent {
                                Text(reminder.calendar.title)
                            } label: {
                                Text("List", bundle: HanlinLocalization.bundle)
                            }
                            LabeledContent {
                                Text(reminder.isCompleted ? "Completed" : "Not completed", bundle: HanlinLocalization.bundle)
                            } label: {
                                Text("Status", bundle: HanlinLocalization.bundle)
                            }
                            if let date = reminderDate(reminder) {
                                LabeledContent {
                                    Text(date, format: .dateTime)
                                } label: {
                                    Text("Due date", bundle: HanlinLocalization.bundle)
                                }
                            }
                        }
                        if let notes = reminder.notes, !notes.isEmpty {
                            Section {
                                Text(notes).textSelection(.enabled)
                            } header: {
                                Text("Notes", bundle: HanlinLocalization.bundle)
                            }
                        }
                    }
                case .unavailable(let message):
                    ContentUnavailableView {
                        Label {
                            Text("Unable to open item", bundle: HanlinLocalization.bundle)
                        } icon: {
                            Image(systemName: "calendar.badge.exclamationmark")
                        }
                    } description: {
                        Text(LocalizedStringKey(message), bundle: HanlinLocalization.bundle)
                    }
                }
            }
            .navigationTitle(Text(item.type == "calendar" ? "Calendar item" : "Reminder", bundle: HanlinLocalization.bundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close", bundle: HanlinLocalization.bundle)
                    }
                }
            }
        }
        .presentationSizing(.form)
        .accessibilityIdentifier("hanlin-calendar-saved-item")
        .task(id: item.resolvedItemIdentifier) {
            guard let identifier = item.resolvedItemIdentifier, !identifier.isEmpty else {
                state = .unavailable("This message does not contain a saved item identifier.")
                return
            }
            do {
                if item.type == "calendar" {
                    state = .event(try await calendarEventForPresentation(item))
                } else if let reminder = try await reminderForPresentation(item) {
                    state = .reminder(reminder)
                } else {
                    state = .unavailable("This item is no longer available.")
                }
            } catch is CancellationError {
                return
            } catch let error as HanlinAppleDeviceServiceError {
                switch error {
                case .denied: state = .unavailable("Calendar or Reminders access was not granted.")
                default: state = .unavailable("This item is no longer available.")
                }
            } catch {
                state = .unavailable("This item is no longer available.")
            }
        }
    }

    private func reminderDate(_ reminder: HanlinScriptReminderItem) -> Date? {
        guard let values = reminder.dueDateComponentValues else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reminder.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        var components = DateComponents()
        components.calendar = calendar; components.timeZone = calendar.timeZone
        components.year = values["year"]; components.month = values["month"]
        components.day = values["day"]; components.hour = values["hour"]
        components.minute = values["minute"]; components.second = values["second"]
        return components.date
    }
}

/// SwiftUI has no public event-detail equivalent. This is Apple's exact-item
/// viewer; editing remains in the requested tool workflow.
@MainActor
private struct EventDetails: UIViewControllerRepresentable {
    let event: EKEvent
    func makeUIViewController(context: Context) -> EKEventViewController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = false
        controller.allowsCalendarPreview = false
        return controller
    }
    func updateUIViewController(_ controller: EKEventViewController, context: Context) {
        controller.event = event
    }
}
