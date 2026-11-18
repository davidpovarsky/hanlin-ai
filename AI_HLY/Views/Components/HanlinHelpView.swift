import SwiftUI

/// Offline help for the existing Hanlin navigation and original runtimes.
struct HanlinHelpView: View {
    enum Topic { case guide, costs }
    let topic: Topic
    var showsDone = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if topic == .guide {
                helpSection("Start a conversation",
                    "Open Profile, then Models to configure a provider and select a chat model. A text optimization model is optional for ordinary conversations.")
                helpSection("Chat and history",
                    "Use Chat to create or reopen a conversation. History keeps the original conversation and its messages. Use the workspace menu for Vision or the separate MiniApps app.")
                helpSection("Your library",
                    "Library contains knowledge, memory, prompts, canvases and saved messages. Opening an item uses its original editor or reader.")
                helpSection("Skills and MiniApps",
                    "Use Profile, then Skill Center to review and import skills. Check the skill files, runtime requirements and requested actions before running them. MiniApps opens the separately installed companion; it must be installed to handle a request.")
                helpSection("Message actions",
                    "Use a message's Select action to select text, copy it, or open Translation, Polish or Summary with that text. Those writing tools require their configured model. A Python canvas can use the on-device runtime or an explicitly selected remote service.")
                helpSection("Keep your data",
                    "Conversations and library items use the app's existing storage. Back up important content before migrating or reinstalling. MiniApps transfer previews identify the data being transferred; inspect the result before removing the original.")
            } else {
                helpSection("Cloud model costs",
                    "Cloud providers bill under your own account and pricing. A request may include conversation history, attachments, tool results and generated output. Check the selected provider's current rates and usage dashboard.")
                helpSection("Tools and external services",
                    "Search, media, remote code execution and other connected services can have separate limits or charges. A model subscription does not automatically include these services. Review the destination before sending data.")
                helpSection("On-device execution",
                    "Local Python runs through Hanlin's embedded runtime without calling a cloud model for that execution. It uses device resources. A script can still call a service itself, and an AI conversation that writes or runs the script can incur model charges.")
                helpSection("Check actual usage",
                    "Usage and cost displays depend on data reported by each provider. Missing usage is not evidence that a request was free. Stop a run when it is no longer needed and verify charges with the provider.")
            }
        }
        .accessibilityIdentifier(topic == .guide ? "hanlin-help-guide" : "hanlin-help-costs")
        .navigationTitle(topic == .guide ? String(localized: "Hanlin guide") : String(localized: "Costs and services"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("hanlin-help-done")
                }
            }
        }
    }

    private func helpSection(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        Section {
            Text(body).textSelection(.enabled)
        } header: {
            Text(title)
        }
    }
}

/// Shares only the displayed build and OS facts after the user's explicit action.
struct HanlinSupportView: View {
    @State private var copied = false

    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Hanlin"
    }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    private var details: String {
        "\(displayName)\nVersion: \(version) (\(build))\n\(UIDevice.current.systemName): \(UIDevice.current.systemVersion)"
    }

    var body: some View {
        Form {
            Section("Support information") {
                Text("Share these build details and the steps that reproduce the issue with the person who supplied your Hanlin build. Review any screenshots or logs before sharing.")
                Text(details).textSelection(.enabled)
                    .accessibilityIdentifier("hanlin-support-details")
                Button {
                    UIPasteboard.general.string = details
                    copied = true
                } label: {
                    Label(copied ? String(localized: "Copied") : String(localized: "Copy build details"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("hanlin-support-copy")
                ShareLink(item: details) {
                    Label("Share build details", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("hanlin-support-share")
            }
            Section("Hanlin project") {
                Link("Project source", destination: URL(string: "https://github.com/davidpovarsky/hanlin-ai")!)
                    .accessibilityIdentifier("hanlin-project-source")
            }
        }
        .accessibilityIdentifier("hanlin-support")
        .navigationTitle(String(localized: "Support information"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
