//
//  ToolPresentationRegistry.swift
//  AI_HLY
//

import Foundation

struct ToolPresentation {
    var title: String
    var systemImage: String
    var runningDescription: String
    var completedDescription: String
    var activityKind: AgentActivityKind
}

enum ToolPresentationRegistry {
    static func presentation(for toolName: String) -> ToolPresentation {
        let normalized = toolName.lowercased()
        if normalized.contains("github") {
            return ToolPresentation(title: String(localized: "Searching GitHub"), systemImage: "chevron.left.forwardslash.chevron.right", runningDescription: String(localized: "Searching GitHub"), completedDescription: String(localized: "Done"), activityKind: .webSearch)
        }
        if normalized.contains("sefaria") {
            return ToolPresentation(title: String(localized: "Searching Sefaria"), systemImage: "book.closed", runningDescription: String(localized: "Searching Sefaria"), completedDescription: String(localized: "Done"), activityKind: .webSearch)
        }
        if normalized.contains("wikipedia") || normalized.contains("wiki") {
            return ToolPresentation(title: String(localized: "Searching Wikipedia"), systemImage: "globe", runningDescription: String(localized: "Searching Wikipedia"), completedDescription: String(localized: "Done"), activityKind: .webSearch)
        }
        if normalized.contains("search") || normalized.contains("web") {
            return ToolPresentation(title: String(localized: "Searching the web"), systemImage: "magnifyingglass", runningDescription: String(localized: "Searching the web"), completedDescription: String(localized: "Done"), activityKind: .webSearch)
        }
        if normalized.contains("document") || normalized.contains("file") || normalized.contains("read") {
            return ToolPresentation(title: String(localized: "Reading a document"), systemImage: "doc.text", runningDescription: String(localized: "Reading a document"), completedDescription: String(localized: "Done"), activityKind: .documentRead)
        }
        if normalized.contains("code") || normalized.contains("python") || normalized.contains("calculate") {
            return ToolPresentation(title: String(localized: "Running code"), systemImage: "terminal", runningDescription: String(localized: "Running code"), completedDescription: String(localized: "Done"), activityKind: .codeExecution)
        }
        if normalized.contains("calendar") || normalized.contains("event") || normalized.contains("reminder") {
            return ToolPresentation(title: String(localized: "Checking the calendar"), systemImage: "calendar", runningDescription: String(localized: "Checking the calendar"), completedDescription: String(localized: "Done"), activityKind: .calendar)
        }
        if normalized.contains("location") || normalized.contains("map") || normalized.contains("route") || normalized.contains("weather") {
            return ToolPresentation(title: String(localized: "Searching locations"), systemImage: "map", runningDescription: String(localized: "Searching locations"), completedDescription: String(localized: "Done"), activityKind: .map)
        }
        if normalized.contains("health") || normalized.contains("nutrition") || normalized.contains("step") || normalized.contains("energy") {
            return ToolPresentation(title: String(localized: "Using a tool"), systemImage: "heart.text.square", runningDescription: String(localized: "Using a tool"), completedDescription: String(localized: "Done"), activityKind: .health)
        }
        return ToolPresentation(title: String(localized: "Using a tool"), systemImage: "wrench.and.screwdriver", runningDescription: String(localized: "Using a tool"), completedDescription: String(localized: "Done"), activityKind: .toolExecution)
    }
}
