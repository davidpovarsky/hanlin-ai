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

public struct TextStudioCanonicalRegistration: HanlinStaticMiniAppRegistration, Sendable {
    public let appID = try! HanlinAppID(validating: "nativeapp.textstudio")

    public let descriptor: HanlinAppDescriptor = {
        let appID = try! HanlinAppID(validating: "nativeapp.textstudio")
        let moduleID = try! HanlinModuleID(validating: "nativeapp.textstudio")
        let pasteReadCapID = try! HanlinCapabilityID(validating: "pasteboard.read")
        let pasteWriteCapID = try! HanlinCapabilityID(validating: "pasteboard.write")
        let analyzeToolID = try! HanlinToolID(validating: "text_analyze")
        let transformToolID = try! HanlinToolID(validating: "text_transform")
        let providerID = try! HanlinProviderInstanceID(validating: "native.app.nativeapp.textstudio")
        let version = try! HanlinPackageVersion(validating: "1.0.0")
        return try! HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: HanlinDescriptorRevision(1),
            id: appID,
            name: LocalizedValue(["en": "Text Studio", "he": "סטודיו טקסט"]),
            summary: LocalizedValue(["en": "Write, inspect, transform and keep history", "he": "כתיבה, בדיקה, המרה ושמירת היסטוריה"]),
            description: LocalizedValue(["en": "Analyze, transform and continue working with text", "he": "ניתוח, המרה והמשך עבודה עם טקסט"]),
            version: version,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "textformat.alt"),
            appearance: .init(accentHex: "#F06FB5", isBeta: false),
            category: .productivity,
            implementation: .native(moduleID: moduleID),
            entryPoints: [
                HanlinEntryPointDescriptor(kind: .app, handler: "nativeapp.textstudio", allowedContexts: [.mainApplication]),
                HanlinEntryPointDescriptor(kind: .assistantTool, handler: "nativeapp.textstudio", allowedContexts: [.mainApplication]),
                HanlinEntryPointDescriptor(kind: .embeddedResult, handler: "nativeapp.textstudio.analysis.card", allowedContexts: [.mainApplication])
            ],
            tools: [
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(providerInstanceID: providerID, localToolID: analyzeToolID),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Analyze Text"]),
                    summary: LocalizedValue(["en": "Analyze text structure and content"]),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object(["text": .object(["type": .string("string"), "minLength": .integer(1)])]),
                            "required": .array([.string("text")])
                        ])
                    ),
                    capabilities: [],
                    risk: .passive,
                    presentation: .init(
                        compactStyle: .text,
                        supportsExpandedPresentation: true,
                        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                            handler: "nativeapp.textstudio.analysis.card",
                            sizing: HanlinEmbeddedSizingPreference(preset: .regular)
                        )
                    )
                ),
                HanlinToolDescriptor(
                    logicalID: HanlinLogicalToolID(providerInstanceID: providerID, localToolID: transformToolID),
                    descriptorRevision: HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: LocalizedValue(["en": "Transform Text"]),
                    summary: LocalizedValue(["en": "Transform text content"]),
                    inputSchema: HanlinJSONSchemaDocument(
                        dialect: .draft2020_12,
                        root: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "text": .object(["type": .string("string"), "minLength": .integer(1)]),
                                "action": .object(["type": .string("string")])
                            ]),
                            "required": .array([.string("text")])
                        ])
                    ),
                    capabilities: [pasteWriteCapID],
                    risk: .write,
                    presentation: .init(compactStyle: .text, supportsExpandedPresentation: true)
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(id: pasteReadCapID, reason: LocalizedValue(["en": "Imports text from the clipboard."]), constraints: .object([:]), optional: true, risk: .sensitiveRead),
                HanlinCapabilityDeclaration(id: pasteWriteCapID, reason: LocalizedValue(["en": "Copies transformed text and analysis results."]), constraints: .object([:]), optional: true, risk: .sensitiveRead)
            ],
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment])
        )
    }()

    public init() {}
}

// MARK: - Provider

public struct TextStudioMiniAppProvider: HanlinCompiledMiniAppProvider, Sendable {
    public let registration: any HanlinStaticMiniAppRegistration
    public var appID: HanlinAppID { registration.appID }
    public var descriptor: HanlinAppDescriptor { (try? registration.appDescriptor())! }

    public init(registration: TextStudioCanonicalRegistration = TextStudioCanonicalRegistration()) {
        self.registration = registration
    }

    #if canImport(SwiftUI)
    @MainActor
    public func makeRootView(context: HanlinMiniAppHostContext) -> AnyView {
        let initialText: String?
        let storage: UserDefaultsTextStudioStorage
        if case let .object(input) = context.sharedInput {
            let prefix: String
            if case let .string(requestID) = input["requestID"] {
                prefix = "hanlin.miniapps." + requestID + "."
            } else { prefix = "" }
            storage = UserDefaultsTextStudioStorage(keyPrefix: prefix)
            if !prefix.isEmpty, let restored = storage.persistentString(forKey: "draft") {
                initialText = restored
            } else if case let .string(text) = input["text"] {
                initialText = text
            } else { initialText = nil }
        } else {
            storage = UserDefaultsTextStudioStorage()
            initialText = nil
        }
        let onReturn: (@MainActor @Sendable (String) async throws -> Void)?
        if let complete = context.completeSharedRequest {
            onReturn = { text in try await complete(.string(text)) }
        } else {
            onReturn = nil
        }
        return AnyView(NavigationStack {
            NativeAppTextStudioRootView(storage: storage, initialText: initialText, onReturn: onReturn)
                .hanlinMiniAppDismissControl()
        })
    }
    #endif
}

#if canImport(SwiftUI)
public typealias TextStudioMiniAppView = NativeAppTextStudioRootView
#endif

