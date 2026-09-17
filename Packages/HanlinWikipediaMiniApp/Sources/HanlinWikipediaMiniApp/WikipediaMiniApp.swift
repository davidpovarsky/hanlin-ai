import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
#if canImport(Observation)
import Observation
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Registration

public struct WikipediaCanonicalRegistration: HanlinStaticMiniAppRegistration, Sendable {
    public let appID = try! HanlinAppID(validating: "nativeapp.wikipedia")

    public let descriptor: HanlinAppDescriptor = {
        let appID = try! HanlinAppID(validating: "nativeapp.wikipedia")
        let moduleID = try! HanlinModuleID(validating: "nativeapp.wikipedia")
        let networkCapID = try! HanlinCapabilityID(validating: "network.fetch")
        let pasteCapID = try! HanlinCapabilityID(validating: "pasteboard.write")
        let searchToolID = try! HanlinToolID(validating: "wikipedia_search")
        let summaryToolID = try! HanlinToolID(validating: "wikipedia_get_summary")
        let providerID = try! HanlinProviderInstanceID(validating: "native.app.nativeapp.wikipedia")
        let version = try! HanlinPackageVersion(validating: "1.0.0")
        return try! HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Wikipedia", "he": "ויקיפדיה"]),
            summary: LocalizedValue(["en": "Explore, save and revisit knowledge", "he": "חקירה, שמירה ועיון בידע"]),
            description: LocalizedValue(["en": "Search articles and read encyclopedia summaries", "he": "חיפוש מאמרים וקריאת תקצירי אנציקלופדיה"]),
            version: version,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "globe.americas.fill"),
            appearance: .init(accentHex: "#4C83E8", isBeta: false),
            category: .knowledge,
            implementation: .native(moduleID: moduleID),
            entryPoints: [
                HanlinEntryPointDescriptor(kind: .app, handler: "nativeapp.wikipedia", allowedContexts: [.mainApplication]),
                HanlinEntryPointDescriptor(kind: .assistantTool, handler: "nativeapp.wikipedia", allowedContexts: [.mainApplication]),
                HanlinEntryPointDescriptor(kind: .embeddedResult, handler: "nativeapp.wikipedia.summary.card", allowedContexts: [.mainApplication])
            ],
            tools: [
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(providerInstanceID: providerID, localToolID: searchToolID),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Search Wikipedia"]),
                    summary: LocalizedValue(["en": "Search Wikipedia articles"]),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object(["query": .object(["type": .string("string"), "minLength": .integer(1)])]),
                            "required": .array([.string("query")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .search,
                        supportsExpandedPresentation: true,
                        executionPresentation: HanlinToolExecutionPresentationDescriptor(familyID: .webSearch),
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.wikipedia.results",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
                        )
                    )
                ),
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(providerInstanceID: providerID, localToolID: summaryToolID),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Wikipedia Summary"]),
                    summary: LocalizedValue(["en": "Get a summary of a Wikipedia article"]),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object(["title": .object(["type": .string("string"), "minLength": .integer(1)])]),
                            "required": .array([.string("title")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .entity,
                        supportsExpandedPresentation: true,
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.wikipedia.summary.card",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
                        )
                    )
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(id: networkCapID, reason: LocalizedValue(["en": "Searches and opens Wikipedia articles."]), constraints: .object(["domain": .string("wikipedia.org")]), risk: .read),
                HanlinCapabilityDeclaration(id: pasteCapID, reason: LocalizedValue(["en": "Copies article summaries."]), constraints: .object([:]), optional: true, risk: .sensitiveRead)
            ],
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment])
        )
    }()

    public init() {}
}

// MARK: - Provider

public struct WikipediaMiniAppProvider: HanlinCompiledMiniAppProvider, Sendable {
    public let registration: any HanlinStaticMiniAppRegistration
    public var appID: HanlinAppID { registration.appID }
    public var descriptor: HanlinAppDescriptor { (try? registration.appDescriptor())! }

    public init(registration: WikipediaCanonicalRegistration = WikipediaCanonicalRegistration()) {
        self.registration = registration
    }

    #if canImport(SwiftUI)
    @MainActor
    public func makeRootView(context: HanlinMiniAppHostContext) -> AnyView {
        AnyView(NavigationStack {
            NativeAppWikipediaRootView()
        })
    }
    #endif
}

#if canImport(SwiftUI)
public typealias WikipediaMiniAppView = NativeAppWikipediaRootView
#endif

