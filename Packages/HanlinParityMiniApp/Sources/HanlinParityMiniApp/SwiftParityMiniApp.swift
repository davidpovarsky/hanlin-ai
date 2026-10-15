import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptUI
#if canImport(Observation)
import Observation
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Registration

public struct SwiftParityMiniAppRegistration: HanlinStaticMiniAppRegistration, Sendable {
    public let descriptor: HanlinAppDescriptor
    public var appID: HanlinAppID { descriptor.id }

    public init() {
        do {
            let appID = try HanlinAppID(validating: "hanlin.demo.swift-parity")
            let shareCapability = try HanlinCapabilityID(validating: "inter-app.share")
            descriptor = HanlinAppDescriptor(
                schemaVersion: .init(major: 1, minor: 0),
                descriptorRevision: try HanlinDescriptorRevision(1),
                id: appID,
                name: try LocalizedValue(["en": "Swift Parity", "he": "מקבילת Swift"]),
                summary: try LocalizedValue(["en": "Native SwiftPM Mini App", "he": "Mini App מקבילת SwiftPM"]),
                description: try LocalizedValue(["en": "A real Swift Package Mini App proving canonical storage and sharing.", "he": "חבילת Swift אמיתית שמדגימה אחסון ושיתוף קנוניים."]),
                version: try HanlinPackageVersion(validating: "1.0.0"),
                apiVersion: .init(major: 1, minor: 0),
                icon: .systemSymbol(name: "swift"),
                appearance: .init(accentHex: "#F05138", preferredColorScheme: .system),
                category: .developer,
                implementation: .native(moduleID: try HanlinModuleID(validating: "hanlin.demo.swift-parity")),
                entryPoints: [
                    .init(kind: .app, handler: "SwiftParityMiniAppView", allowedContexts: [.mainApplication]),
                    .init(kind: .widget, handler: "SwiftParityMiniAppExposures.widget", allowedContexts: [.widget]),
                    .init(kind: .appIntentBridge, handler: "SwiftParityMiniAppExposures.performIntent", allowedContexts: [.appIntent])
                ],
                capabilities: [
                    .init(id: try HanlinCapabilityID(validating: "storage"), reason: try LocalizedValue(["en": "Persist demo state privately."]), constraints: .object([:]), risk: .write),
                    .init(id: try HanlinCapabilityID(validating: "network"), reason: try LocalizedValue(["en": "Run the HTTPS parity check."]), constraints: .object(["schemes": .array([.string("https")])]), optional: true, risk: .sensitiveRead),
                    .init(id: shareCapability, reason: try LocalizedValue(["en": "Exchange an explicitly authorized demo value."]), constraints: .object([:]), optional: true, risk: .sensitiveRead)
                ],
                authors: [.init(name: "Hanlin")],
                distribution: .init(sourceVisible: true, sourceEditable: false, remoteUpdates: false, allowedModes: [.personalDevelopment, .testFlight])
            )
            try descriptor.validate()
        } catch {
            preconditionFailure("Invalid built-in Swift parity descriptor: \(error)")
        }
    }
}

// MARK: - Exposures

public enum SwiftParityMiniAppExposures {
    public struct PersistedState: Codable, Sendable, Equatable {
        public let counter: Int
        public let name: String

        public init(counter: Int, name: String) {
            self.counter = counter
            self.name = name
        }
    }

    public static func decodeState(from persistedData: Data?) throws -> PersistedState {
        guard let persistedData, !persistedData.isEmpty else {
            return PersistedState(counter: 0, name: "Hanlin")
        }
        return try JSONDecoder().decode(PersistedState.self, from: persistedData)
    }

    public static func widget(family: String, persistedData: Data?) throws -> HanlinScriptUINode {
        let state = try decodeState(from: persistedData)
        return .init(
            kind: .vStack,
            properties: ["spacing": .number(8)],
            children: [
                .init(kind: .text, properties: ["content": .string(state.name), "font": .string("headline")]),
                .init(kind: .text, properties: ["content": .string("Counter: \(state.counter)"), "font": .string("body")]),
                .init(kind: .text, properties: ["content": .string("Swift Parity · \(family)"), "font": .string("caption")])
            ]
        )
    }

    public enum IntentError: Error, LocalizedError, Sendable {
        case unsupportedIntent(String)
        public var errorDescription: String? {
            switch self {
            case .unsupportedIntent(let name):
                return "Unsupported intent: \(name)"
            }
        }
    }

    public static func performIntent(name: String, parameters: HanlinValue, persistedData: Data?) throws -> HanlinValue {
        guard name == "ReadSwiftParityState" else {
            throw IntentError.unsupportedIntent(name)
        }
        let state = try decodeState(from: persistedData)
        return .object([
            "appID": .string("hanlin.demo.swift-parity"),
            "name": .string(state.name),
            "counter": .integer(Int64(state.counter))
        ])
    }
}

// MARK: - Provider

public struct SwiftParityMiniAppProvider: HanlinCompiledMiniAppProvider, Sendable {
    public let registration: any HanlinStaticMiniAppRegistration
    public var appID: HanlinAppID { registration.appID }
    public var descriptor: HanlinAppDescriptor { (try? registration.appDescriptor())! }

    public init(registration: SwiftParityMiniAppRegistration = SwiftParityMiniAppRegistration()) {
        self.registration = registration
    }

    #if canImport(SwiftUI)
    @MainActor
    public func makeRootView(context: HanlinMiniAppHostContext) -> AnyView {
        AnyView(NavigationStack {
            SwiftParityMiniAppView(
                storage: context.storage,
                requestBroker: context.requestBroker,
                network: context.network,
                onWidgetRefreshRequested: context.requestWidgetRefresh
            )
        })
    }
    #endif
}

#if canImport(SwiftUI)
// MARK: - View

public struct SwiftParityMiniAppView: View {
    @State private var model: Model

    public init(
        storage: HanlinMiniAppStorageContext,
        requestBroker: HanlinMiniAppRequestBroker,
        network: @escaping @Sendable (URL) async throws -> String,
        onWidgetRefreshRequested: (@MainActor @Sendable () -> Void)? = nil
    ) {
        _model = State(initialValue: Model(
            storage: storage,
            requestBroker: requestBroker,
            network: network,
            onWidgetRefreshRequested: onWidgetRefreshRequested
        ))
    }

    public var body: some View {
        Form {
            Section("Private durable state") {
                Stepper("Counter: \(model.counter)", value: $model.counter)
                TextField("Name", text: $model.name)
                HStack {
                    Button("Save") { Task { await model.save() } }
                    Button("Reload") { Task { await model.reload() } }
                }
                Text(model.storageStatus).foregroundStyle(.secondary)
            }

            Section("Brokered services") {
                Button("HTTPS network test") { Task { await model.runNetworkTest() } }
                Text(model.networkStatus).foregroundStyle(.secondary)
                Button("Request NativeScript value") { Task { await model.requestScriptValue() } }
                Text(model.sharingStatus).foregroundStyle(.secondary)
            }

            Section("Canonical diagnostics") {
                LabeledContent("Mini App ID", value: Model.appID.rawValue)
                LabeledContent("Engine", value: "SwiftPM")
                LabeledContent("Entrypoint", value: "SwiftParityMiniAppView")
            }
        }
        .navigationTitle("Swift Parity")
        .task { await model.activate() }
    }
}

// MARK: - Model

@MainActor
@Observable
private final class Model {
    nonisolated static let appID = try! HanlinAppID(validating: "hanlin.demo.swift-parity")
    nonisolated static let scriptID = try! HanlinAppID(validating: "hanlin.demo.script-parity")
    nonisolated static let action = try! HanlinActionID(validating: "share.value")
    nonisolated static let capability = try! HanlinCapabilityID(validating: "inter-app.share")

    var counter = 0
    var name = "Hanlin"
    var storageStatus = "Not loaded"
    var networkStatus = "Not run"
    var sharingStatus = "Not requested"

    private let storage: HanlinMiniAppStorageContext
    private let requestBroker: HanlinMiniAppRequestBroker
    private let network: @Sendable (URL) async throws -> String
    private let onWidgetRefreshRequested: (@MainActor @Sendable () -> Void)?

    init(
        storage: HanlinMiniAppStorageContext,
        requestBroker: HanlinMiniAppRequestBroker,
        network: @escaping @Sendable (URL) async throws -> String,
        onWidgetRefreshRequested: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.storage = storage
        self.requestBroker = requestBroker
        self.network = network
        self.onWidgetRefreshRequested = onWidgetRefreshRequested
    }

    func activate() async {
        let store = storage
        await requestBroker.register(
            target: Self.appID,
            action: Self.action,
            capability: Self.capability
        ) { request in
            guard request.caller == Self.scriptID else { throw HanlinMiniAppRequestError.unauthorized }
            let data = try await store.read(area: .state, path: "parity.json")
            let state = try SwiftParityMiniAppExposures.decodeState(from: data)
            return .object(["name": .string(state.name), "counter": .integer(Int64(state.counter))])
        }
        await reload()
    }

    func save() async {
        do {
            let value = SwiftParityMiniAppExposures.PersistedState(counter: counter, name: name)
            try await storage.write(
                JSONEncoder().encode(value),
                area: .state,
                path: "parity.json"
            )
            storageStatus = "Saved in canonical private container"
            onWidgetRefreshRequested?()
        } catch {
            storageStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    func reload() async {
        do {
            guard let data = try await storage.read(area: .state, path: "parity.json") else {
                storageStatus = "No saved value yet"
                return
            }
            let value = try SwiftParityMiniAppExposures.decodeState(from: data)
            counter = value.counter
            name = value.name
            storageStatus = "Reloaded persisted value"
        } catch {
            storageStatus = "Reload failed: \(error.localizedDescription)"
        }
    }

    func runNetworkTest() async {
        do {
            guard let url = URL(string: "https://en.wikipedia.org/") else {
                networkStatus = "Network failed: invalid demo URL"
                return
            }
            let result = try await network(url)
            networkStatus = result
        } catch {
            networkStatus = "Network failed: \(error.localizedDescription)"
        }
    }

    func requestScriptValue() async {
        do {
            let response = try await requestBroker.request(.init(
                caller: Self.appID,
                target: Self.scriptID,
                action: Self.action,
                capability: Self.capability,
                payload: .object(["requested": .string("parity-state")])
            ))
            sharingStatus = String(decoding: try response.value.canonicalJSONData(), as: UTF8.self)
        } catch {
            sharingStatus = "Request denied/unavailable: \(error.localizedDescription)"
        }
    }
}
#endif
