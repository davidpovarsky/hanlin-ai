import SwiftUI
import HanlinPresentationKit

/// A native, live catalogue of the exact tokens used by the app and chat SDK.
/// Sample controls own local state and never call tools or modify preferences.
public struct HanlinComponentCatalogView: View {
    @State private var query = ""
    @State private var isEnabled = true
    @State private var selected = 0
    @State private var amount = 0.5

    public init() {}

    public var body: some View {
        List {
            Section("Typography") {
                Text("Large title").font(HanlinTypography.largeTitle)
                Text("Title").font(HanlinTypography.title)
                Text("Section heading").font(HanlinTypography.title2)
                Text("Subsection heading").font(HanlinTypography.title3)
                Text("Headline").font(HanlinTypography.headline)
                Text("Body · עברית · English · 中文").font(HanlinTypography.body)
                Text("Secondary text").font(HanlinTypography.subheadline)
                Text("Callout").font(HanlinTypography.callout)
                Text("Supporting text").font(HanlinTypography.footnote)
                Text("Caption").font(HanlinTypography.caption)
                Text("Metadata").font(HanlinTypography.caption2)
            }
            Section("System controls") {
                Toggle("Enabled", isOn: $isEnabled)
                Picker("Selection", selection: $selected) {
                    Text("First").tag(0)
                    Text("Second").tag(1)
                }
                Slider(value: $amount) { Text("Value") }
                Button("Action", systemImage: "checkmark") {}
                Menu("Menu", systemImage: "ellipsis") {
                    Button("First action", systemImage: "star") {}
                    Button("Second action", systemImage: "square.and.arrow.up") {}
                }
            }
            Section("Inline search") {
                #if canImport(UIKit)
                HanlinSearchField(text: $query, prompt: String(localized: "Search"),
                    accessibilityIdentifier: "hanlin-catalog-search")
                #else
                TextField("Search", text: $query)
                #endif
            }
            Section("Appearance") {
                Label("Accent", systemImage: "circle.fill").foregroundStyle(.tint)
                Label("Primary text", systemImage: "textformat").foregroundStyle(.primary)
                Label("Secondary text", systemImage: "textformat").foregroundStyle(.secondary)
                LabeledContent("Minimum touch target", value: "\(Int(HanlinControlMetrics.minimumHitTarget)) pt")
                LabeledContent("Page inset", value: "\(Int(HanlinControlMetrics.pageInset)) pt")
            }
        }
        .font(HanlinTypography.body)
        .navigationTitle("Interface catalogue")
        .accessibilityIdentifier("hanlin-component-catalogue")
    }
}
