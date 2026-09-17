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

public struct SefariaCanonicalRegistration: HanlinStaticMiniAppRegistration, Sendable {
    public let appID = try! HanlinAppID(validating: "nativeapp.sefaria")

    public let descriptor: HanlinAppDescriptor = {
        let appID = try! HanlinAppID(validating: "nativeapp.sefaria")
        let moduleID = try! HanlinModuleID(validating: "nativeapp.sefaria")
        let networkCapID = try! HanlinCapabilityID(validating: "network.fetch")
        let pasteCapID = try! HanlinCapabilityID(validating: "pasteboard.write")
        let toolID = try! HanlinToolID(validating: "sefaria_search")
        let sourceToolID = try! HanlinToolID(validating: "sefaria_get_source")
        let providerID = try! HanlinProviderInstanceID(validating: "native.app.nativeapp.sefaria")
        let version = try! HanlinPackageVersion(validating: "1.0.0")
        return try! HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Sefaria", "he": "ספריא"]),
            summary: LocalizedValue(["en": "Search, read, save and revisit sources", "he": "חיפוש, קריאה ושמירת מקורות"]),
            description: LocalizedValue(["en": "Search and read Jewish texts and sources", "he": "חיפוש וקריאה של טקסטים ומקורות יהודיים"]),
            version: version,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "books.vertical.fill"),
            appearance: .init(accentHex: "#5CB88A", isBeta: false),
            category: .knowledge,
            implementation: .native(moduleID: moduleID),
            entryPoints: [
                HanlinEntryPointDescriptor(kind: .app, handler: "nativeapp.sefaria", allowedContexts: [.mainApplication]),
                HanlinEntryPointDescriptor(kind: .assistantTool, handler: "nativeapp.sefaria", allowedContexts: [.mainApplication]),
                HanlinEntryPointDescriptor(kind: .embeddedResult, handler: "nativeapp.sefaria.source.card", allowedContexts: [.mainApplication])
            ],
            tools: [
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(providerInstanceID: providerID, localToolID: toolID),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Search Sefaria"]),
                    summary: LocalizedValue(["en": "Search Jewish texts in the Sefaria library"]),
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
                        executionPresentation: HanlinToolExecutionPresentationDescriptor(familyID: .sourceSearch),
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.sefaria.results",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
                        )
                    )
                ),
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(providerInstanceID: providerID, localToolID: sourceToolID),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Get Sefaria Source"]),
                    summary: LocalizedValue(["en": "Retrieve a specific Jewish text source"]),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object(["ref": .object(["type": .string("string"), "minLength": .integer(1)])]),
                            "required": .array([.string("ref")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .entity,
                        supportsExpandedPresentation: true,
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.sefaria.source.card",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen], expandedHandler: "nativeapp.sefaria.reader")
                        )
                    )
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(id: networkCapID, reason: LocalizedValue(["en": "Searches and opens Jewish texts."]), constraints: .object(["domain": .string("sefaria.org")]), risk: .read),
                HanlinCapabilityDeclaration(id: pasteCapID, reason: LocalizedValue(["en": "Copies references and source text."]), constraints: .object([:]), optional: true, risk: .sensitiveRead)
            ],
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment])
        )
    }()

    public init() {}
}

// MARK: - Provider

public struct SefariaMiniAppProvider: HanlinCompiledMiniAppProvider, Sendable {
    public let registration: any HanlinStaticMiniAppRegistration
    public var appID: HanlinAppID { registration.appID }
    public var descriptor: HanlinAppDescriptor { (try? registration.appDescriptor())! }

    public init(registration: SefariaCanonicalRegistration = SefariaCanonicalRegistration()) {
        self.registration = registration
    }

    #if canImport(SwiftUI)
    @MainActor
    public func makeRootView(context: HanlinMiniAppHostContext) -> AnyView {
        AnyView(NavigationStack {
            NativeAppSefariaRootView()
        })
    }
    #endif
}

#if canImport(SwiftUI)
public typealias SefariaMiniAppView = NativeAppSefariaRootView
#endif

