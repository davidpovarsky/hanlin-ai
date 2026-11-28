import Foundation
import HanlinPresentationKit

public enum OpenUICatalogs {
    public static func original() throws -> ComponentCatalogDescriptor { try catalog("original", prompt: "original-prompt") }
    public static func torah() throws -> ComponentCatalogDescriptor { try catalog("torah", prompt: "torah-prompt") }

    public static func host(appID: String, research: Bool = false, capabilities: Set<String> = []) throws -> HostPresentationDescriptor {
        let original = try original()
        let torah = try torah()
        let standard = PresentationProfile(id: "hanlin.standard", shellID: "hanlin.standard",
            catalogIDs: [original.reference], capabilities: capabilities)
        let scholar = PresentationProfile(id: "hanlin.research", shellID: "hanlin.research",
            catalogIDs: [torah.reference], capabilities: capabilities, sourcePresentation: .sidebar)
        return .init(appID: appID, defaultProfile: research ? scholar.reference : standard.reference,
            availableProfiles: [standard, scholar], catalogProviders: [original, torah],
            shells: [.init(id: "hanlin.standard", title: "Hanlin"),
                     .init(id: "hanlin.research", title: "Research", usesSourcesSidebar: true)],
            hostCapabilities: capabilities)
    }

    public static func instructions(for profile: ResolvedPresentationProfile) -> String {
        let mode = profile.profile.answerMode == .fullOpenUI
            ? "The selected conversation uses full OpenUI: place the complete answer in one openui-lang fence."
            : "The selected conversation uses mixed Markdown and OpenUI: keep prose as Markdown and embed rich blocks where useful."
        let targets = profile.renderTargets.map(\.rawValue).sorted().joined(separator: ", ")
        return profile.catalogs.map(\.modelInstructions).joined(separator: "\n\n")
            + "\n\n" + mode + " Host-approved render targets for this conversation: " + targets + "."
    }

    public static var resourceDirectory: URL? { Bundle.module.url(forResource: "OpenUI", withExtension: nil) }
    private static func catalog(_ key: String, prompt: String) throws -> ComponentCatalogDescriptor {
        guard let directory = resourceDirectory else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: directory.appending(path: "catalog-manifest.json"))
        let manifest = try JSONDecoder().decode(CatalogManifest.self, from: data)
        let item = key == "torah" ? manifest.torah : manifest.original
        let instructions = try String(contentsOf: directory.appending(path: prompt + ".txt"), encoding: .utf8)
        return .init(reference: .init(item.id, version: item.version), renderTargets: [.react, .swiftui],
                     componentNames: item.components, modelInstructions: instructions)
    }
    private struct CatalogManifest: Decodable {
        struct Catalog: Decodable { let id: String; let version: Int; let components: [String] }
        let original: Catalog; let torah: Catalog
    }
}
