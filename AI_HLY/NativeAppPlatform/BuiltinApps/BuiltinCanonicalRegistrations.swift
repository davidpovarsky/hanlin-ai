import Foundation
import HanlinPlatformContracts

// MARK: - Built-in Canonical Registrations

/// Canonical registrations for built-in native Mini Apps.
///
/// These produce `HanlinAppDescriptor` instances directly from compiled constants,
/// serving as the canonical source of truth. The legacy `NativeAppManifest` and
/// `NativeAppCanonicalShadowAdapter` can be retired once all consumers adopt this.

// MARK: Sefaria

struct SefariaCanonicalRegistration: HanlinStaticMiniAppRegistration {
    let appID = try! HanlinAppID(validating: "nativeapp.sefaria")

    let descriptor: HanlinAppDescriptor = {
        let appID = try! HanlinAppID(validating: "nativeapp.sefaria")
        let moduleID = try! HanlinModuleID(validating: "nativeapp.sefaria")
        let networkCapID = try! HanlinCapabilityID(validating: "network.fetch")
        let pasteCapID = try! HanlinCapabilityID(validating: "pasteboard.write")
        let toolID = try! HanlinToolID(validating: "sefaria-search")
        let sourceToolID = try! HanlinToolID(validating: "sefaria-get-source")
        let providerID = try! HanlinProviderInstanceID(
            validating: "native.app.nativeapp.sefaria"
        )
        let version = try! HanlinPackageVersion(validating: "1.0.0")
        return try! HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Sefaria", "he": "ספריא"]),
            summary: LocalizedValue(
                ["en": "Search, read, save and revisit sources",
                 "he": "חיפוש, קריאה ושמירת מקורות"]
            ),
            description: LocalizedValue(
                ["en": "Search and read Jewish texts and sources",
                 "he": "חיפוש וקריאה של טקסטים ומקורות יהודיים"]
            ),
            version: version,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "books.vertical.fill"),
            appearance: .init(accentHex: "#5CB88A"),
            category: .knowledge,
            implementation: .native(moduleID: moduleID),
            entryPoints: [
                HanlinEntryPointDescriptor(
                    kind: .app,
                    handler: "nativeapp.sefaria",
                    allowedContexts: [.mainApplication]
                ),
                HanlinEntryPointDescriptor(
                    kind: .assistantTool,
                    handler: "nativeapp.sefaria",
                    allowedContexts: [.mainApplication]
                ),
                HanlinEntryPointDescriptor(
                    kind: .embeddedResult,
                    handler: "nativeapp.sefaria",
                    allowedContexts: [.mainApplication]
                )
            ],
            tools: [
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerID,
                        localToolID: toolID
                    ),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Search Sefaria"]),
                    summary: LocalizedValue(
                        ["en": "Search Jewish texts in the Sefaria library"]
                    ),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "query": .object([
                                    "type": .string("string"),
                                    "minLength": .integer(1)
                                ])
                            ]),
                            "required": .array([.string("query")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .search,
                        supportsExpandedPresentation: true,
                        executionPresentation: HanlinToolExecutionPresentationDescriptor(
                            familyID: .sourceSearch
                        ),
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.sefaria.results",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(
                                supportedModes: [.sheet, .fullScreen]
                            )
                        )
                    )
                ),
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerID,
                        localToolID: sourceToolID
                    ),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Get Sefaria Source"]),
                    summary: LocalizedValue(
                        ["en": "Retrieve a specific Jewish text source"]
                    ),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "ref": .object([
                                    "type": .string("string"),
                                    "minLength": .integer(1)
                                ])
                            ]),
                            "required": .array([.string("ref")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .entity,
                        supportsExpandedPresentation: true,
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.sefaria.source",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(
                                supportedModes: [.sheet, .fullScreen],
                                expandedHandler: "nativeapp.sefaria.reader"
                            )
                        )
                    )
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(
                    id: networkCapID,
                    reason: LocalizedValue(
                        ["en": "Searches and opens Jewish texts."]
                    ),
                    constraints: .object(["domain": .string("sefaria.org")]),
                    risk: .read
                ),
                HanlinCapabilityDeclaration(
                    id: pasteCapID,
                    reason: LocalizedValue(
                        ["en": "Copies references and source text."]
                    ),
                    constraints: .object([:]),
                    optional: true,
                    risk: .sensitiveRead
                )
            ],
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: false,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )
    }()
}

// MARK: Wikipedia

struct WikipediaCanonicalRegistration: HanlinStaticMiniAppRegistration {
    let appID = try! HanlinAppID(validating: "nativeapp.wikipedia")

    let descriptor: HanlinAppDescriptor = {
        let appID = try! HanlinAppID(validating: "nativeapp.wikipedia")
        let moduleID = try! HanlinModuleID(validating: "nativeapp.wikipedia")
        let networkCapID = try! HanlinCapabilityID(validating: "network.fetch")
        let pasteCapID = try! HanlinCapabilityID(validating: "pasteboard.write")
        let searchToolID = try! HanlinToolID(validating: "wikipedia-search")
        let summaryToolID = try! HanlinToolID(validating: "wikipedia-summary")
        let providerID = try! HanlinProviderInstanceID(
            validating: "native.app.nativeapp.wikipedia"
        )
        let version = try! HanlinPackageVersion(validating: "1.0.0")
        return try! HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Wikipedia", "he": "ויקיפדיה"]),
            summary: LocalizedValue(
                ["en": "Explore, save and revisit knowledge",
                 "he": "חקירה, שמירה ועיון בידע"]
            ),
            description: LocalizedValue(
                ["en": "Search articles and read encyclopedia summaries",
                 "he": "חיפוש מאמרים וקריאת תקצירי אנציקלופדיה"]
            ),
            version: version,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "globe.americas.fill"),
            appearance: .init(accentHex: "#4C83E8"),
            category: .knowledge,
            implementation: .native(moduleID: moduleID),
            entryPoints: [
                HanlinEntryPointDescriptor(
                    kind: .app,
                    handler: "nativeapp.wikipedia",
                    allowedContexts: [.mainApplication]
                ),
                HanlinEntryPointDescriptor(
                    kind: .assistantTool,
                    handler: "nativeapp.wikipedia",
                    allowedContexts: [.mainApplication]
                ),
                HanlinEntryPointDescriptor(
                    kind: .embeddedResult,
                    handler: "nativeapp.wikipedia",
                    allowedContexts: [.mainApplication]
                )
            ],
            tools: [
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerID,
                        localToolID: searchToolID
                    ),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Search Wikipedia"]),
                    summary: LocalizedValue(
                        ["en": "Search Wikipedia articles"]
                    ),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "query": .object([
                                    "type": .string("string"),
                                    "minLength": .integer(1)
                                ])
                            ]),
                            "required": .array([.string("query")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .search,
                        supportsExpandedPresentation: true,
                        executionPresentation: HanlinToolExecutionPresentationDescriptor(
                            familyID: .webSearch
                        ),
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.wikipedia.results",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(
                                supportedModes: [.sheet, .fullScreen]
                            )
                        )
                    )
                ),
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerID,
                        localToolID: summaryToolID
                    ),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Wikipedia Summary"]),
                    summary: LocalizedValue(
                        ["en": "Get a summary of a Wikipedia article"]
                    ),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "title": .object([
                                    "type": .string("string"),
                                    "minLength": .integer(1)
                                ])
                            ]),
                            "required": .array([.string("title")])
                        ])
                    ),
                    capabilities: [networkCapID],
                    risk: .read,
                    presentation: .init(
                        compactStyle: .entity,
                        supportsExpandedPresentation: true,
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.wikipedia.summary",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                            expansion: HanlinExpansionDescriptor(
                                supportedModes: [.sheet, .fullScreen]
                            )
                        )
                    )
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(
                    id: networkCapID,
                    reason: LocalizedValue(
                        ["en": "Searches and opens Wikipedia articles."]
                    ),
                    constraints: .object(["domain": .string("wikipedia.org")]),
                    risk: .read
                ),
                HanlinCapabilityDeclaration(
                    id: pasteCapID,
                    reason: LocalizedValue(
                        ["en": "Copies article summaries."]
                    ),
                    constraints: .object([:]),
                    optional: true,
                    risk: .sensitiveRead
                )
            ],
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: false,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )
    }()
}

// MARK: Text Studio

struct TextStudioCanonicalRegistration: HanlinStaticMiniAppRegistration {
    let appID = try! HanlinAppID(validating: "nativeapp.textstudio")

    let descriptor: HanlinAppDescriptor = {
        let appID = try! HanlinAppID(validating: "nativeapp.textstudio")
        let moduleID = try! HanlinModuleID(validating: "nativeapp.textstudio")
        let pasteReadCapID = try! HanlinCapabilityID(validating: "pasteboard.read")
        let pasteWriteCapID = try! HanlinCapabilityID(validating: "pasteboard.write")
        let analyzeToolID = try! HanlinToolID(validating: "textstudio-analyze")
        let transformToolID = try! HanlinToolID(validating: "textstudio-transform")
        let providerID = try! HanlinProviderInstanceID(
            validating: "native.app.nativeapp.textstudio"
        )
        let version = try! HanlinPackageVersion(validating: "1.0.0")
        return try! HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Text Studio", "he": "סטודיו טקסט"]),
            summary: LocalizedValue(
                ["en": "Write, inspect, transform and keep history",
                 "he": "כתיבה, בדיקה, המרה ושמירת היסטוריה"]
            ),
            description: LocalizedValue(
                ["en": "Analyze, transform and continue working with text",
                 "he": "ניתוח, המרה והמשך עבודה עם טקסט"]
            ),
            version: version,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "textformat.alt"),
            appearance: .init(accentHex: "#F06FB5"),
            category: .productivity,
            implementation: .native(moduleID: moduleID),
            entryPoints: [
                HanlinEntryPointDescriptor(
                    kind: .app,
                    handler: "nativeapp.textstudio",
                    allowedContexts: [.mainApplication]
                ),
                HanlinEntryPointDescriptor(
                    kind: .assistantTool,
                    handler: "nativeapp.textstudio",
                    allowedContexts: [.mainApplication]
                ),
                HanlinEntryPointDescriptor(
                    kind: .embeddedResult,
                    handler: "nativeapp.textstudio",
                    allowedContexts: [.mainApplication]
                )
            ],
            tools: [
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerID,
                        localToolID: analyzeToolID
                    ),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Analyze Text"]),
                    summary: LocalizedValue(
                        ["en": "Analyze text structure and content"]
                    ),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "text": .object([
                                    "type": .string("string"),
                                    "minLength": .integer(1)
                                ])
                            ]),
                            "required": .array([.string("text")])
                        ])
                    ),
                    capabilities: [],
                    risk: .passive,
                    presentation: .init(
                        compactStyle: .text,
                        supportsExpandedPresentation: true,
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.textstudio.analysis",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular)
                        )
                    )
                ),
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerID,
                        localToolID: transformToolID
                    ),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Transform Text"]),
                    summary: LocalizedValue(
                        ["en": "Transform text content"]
                    ),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "text": .object([
                                    "type": .string("string"),
                                    "minLength": .integer(1)
                                ]),
                                "action": .object([
                                    "type": .string("string")
                                ])
                            ]),
                            "required": .array([.string("text")])
                        ])
                    ),
                    capabilities: [pasteWriteCapID],
                    risk: .write,
                    presentation: .init(
                        compactStyle: .text,
                        supportsExpandedPresentation: true
                    )
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(
                    id: pasteReadCapID,
                    reason: LocalizedValue(
                        ["en": "Imports text from the clipboard."]
                    ),
                    constraints: .object([:]),
                    optional: true,
                    risk: .sensitiveRead
                ),
                HanlinCapabilityDeclaration(
                    id: pasteWriteCapID,
                    reason: LocalizedValue(
                        ["en": "Copies transformed text and analysis results."]
                    ),
                    constraints: .object([:]),
                    optional: true,
                    risk: .sensitiveRead
                )
            ],
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: false,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )
    }()
}

// MARK: - Built-in Canonical Index

/// Central index of all built-in native Mini App canonical registrations.
///
/// This parallels `BuiltinAppsIndex.modules()` but provides canonical
/// `HanlinAppDescriptor` instances directly, without going through the
/// legacy `NativeAppModule` → `NativeAppCanonicalShadowAdapter` path.
enum BuiltinCanonicalRegistrations {
    static let all: [any HanlinStaticMiniAppRegistration] = [
        SefariaCanonicalRegistration(),
        WikipediaCanonicalRegistration(),
        TextStudioCanonicalRegistration()
    ]

    static func registration(
        for appID: HanlinAppID
    ) -> (any HanlinStaticMiniAppRegistration)? {
        all.first { $0.appID == appID }
    }
}

// MARK: - Built-in Canonical Discovery

/// Discovery service for built-in native Mini Apps conforming to the canonical protocol.
public struct BuiltinMiniAppDiscovery: HanlinMiniAppDiscovery, Sendable {
    public init() {}

    public func registrations() async throws -> [any HanlinMiniAppRegistration] {
        BuiltinCanonicalRegistrations.all
    }

    public func registration(
        for appID: HanlinAppID
    ) async throws -> (any HanlinMiniAppRegistration)? {
        BuiltinCanonicalRegistrations.registration(for: appID)
    }

    public func catalogSnapshot(
        revision: HanlinCatalogRevision = .init(1)
    ) async throws -> HanlinCatalogSnapshot {
        let descriptors = try BuiltinCanonicalRegistrations.all.map {
            try $0.appDescriptor()
        }
        return HanlinCatalogSnapshot(
            revision: revision,
            generatedAt: .now,
            apps: descriptors
        )
    }
}

