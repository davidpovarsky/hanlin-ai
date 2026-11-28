import HanlinLocalization
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
            Section(hanlin: "Typography") {
                Text("Large title", bundle: HanlinLocalization.bundle).font(HanlinTypography.largeTitle)
                Text("Title", bundle: HanlinLocalization.bundle).font(HanlinTypography.title)
                Text("Section heading", bundle: HanlinLocalization.bundle).font(HanlinTypography.title2)
                Text("Subsection heading", bundle: HanlinLocalization.bundle).font(HanlinTypography.title3)
                Text("Headline", bundle: HanlinLocalization.bundle).font(HanlinTypography.headline)
                Text("Body · עברית · English · 中文", bundle: HanlinLocalization.bundle).font(HanlinTypography.body)
                Text("Secondary text", bundle: HanlinLocalization.bundle).font(HanlinTypography.subheadline)
                Text("Callout", bundle: HanlinLocalization.bundle).font(HanlinTypography.callout)
                Text("Supporting text", bundle: HanlinLocalization.bundle).font(HanlinTypography.footnote)
                Text("Caption", bundle: HanlinLocalization.bundle).font(HanlinTypography.caption)
                Text("Metadata", bundle: HanlinLocalization.bundle).font(HanlinTypography.caption2)
            }
            Section(hanlin: "System controls") {
                Toggle(hanlin: "Enabled", isOn: $isEnabled)
                Picker(hanlin: "Selection", selection: $selected) {
                    Text("First", bundle: HanlinLocalization.bundle).tag(0)
                    Text("Second", bundle: HanlinLocalization.bundle).tag(1)
                }
                Slider(value: $amount) { Text("Value", bundle: HanlinLocalization.bundle) }
                Button(hanlin: "Action", systemImage: "checkmark") {}
                Menu(hanlin: "Menu", systemImage: "ellipsis") {
                    Button(hanlin: "First action", systemImage: "star") {}
                    Button(hanlin: "Second action", systemImage: "square.and.arrow.up") {}
                }
            }
            Section(hanlin: "Inline search") {
                #if canImport(UIKit)
                HanlinSearchField(text: $query, prompt: String(localized: "Search", bundle: HanlinLocalization.bundle),
                    accessibilityIdentifier: "hanlin-catalog-search")
                #else
                TextField(hanlin: "Search", text: $query)
                #endif
            }
            Section(hanlin: "Appearance") {
                Label(hanlin: "Accent", systemImage: "circle.fill").foregroundStyle(.tint)
                Label(hanlin: "Primary text", systemImage: "textformat").foregroundStyle(.primary)
                Label(hanlin: "Secondary text", systemImage: "textformat").foregroundStyle(.secondary)
                LabeledContent(hanlin: "Minimum touch target", value: "\(Int(HanlinControlMetrics.minimumHitTarget)) pt")
                LabeledContent(hanlin: "Page inset", value: "\(Int(HanlinControlMetrics.pageInset)) pt")
            }
        }
        .font(HanlinTypography.body)
        .navigationTitle(Text("Interface catalogue", bundle: HanlinLocalization.bundle))
        .accessibilityIdentifier("hanlin-component-catalogue")
    }
}
