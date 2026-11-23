import Foundation
import HanlinMiniAppsBridge
import HanlinMiniAppCore
import HanlinPlatformContracts
import Observation
import SwiftUI
import UIKit

/// An operation belongs to one invocation and one engine session.
public typealias HanlinMiniAppExternalOperation = @MainActor @Sendable (String, String) async throws -> String

@MainActor @Observable
final class HanlinExternalMiniAppSession {
    let requestID: UUID
    private(set) var request: MiniAppInvocation?
    private(set) var view: AnyView?
    private(set) var result: MiniAppResult?
    private(set) var loading = false
    private(set) var returning = false
    var error: String?
    private var platform: HanlinScriptingPlatform?
    private var provider: HanlinMiniAppsProvider?
    private var loadGeneration = UUID()

    private let storeOverride: MiniAppBridgeStore?
    private let openSource: @MainActor (URL) async -> Bool

    init(requestID: UUID, store: MiniAppBridgeStore? = nil,
         openSource: @escaping @MainActor (URL) async -> Bool = HanlinExternalMiniAppSession.openSourceApplication) {
        self.requestID = requestID
        self.storeOverride = store
        self.openSource = openSource
    }

    private func mailbox() throws -> MiniAppBridgeStore {
        if let storeOverride { return storeOverride }
        return try MiniAppBridgeStore()
    }

    @discardableResult
    func restoreRequest() throws -> MiniAppInvocation {
        guard let request = try mailbox().request(id: requestID) else {
            throw failure("The shared request could not be found.")
        }
        self.request = request
        self.result = try mailbox().result(id: requestID)
        return request
    }

    private static func openSourceApplication(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
        }
    }

    func load() async {
        guard request == nil, !loading else { return }
        loading = true
        let generation = UUID()
        loadGeneration = generation
        var ownedPlatform: HanlinScriptingPlatform?
        defer { if loadGeneration == generation { loading = false } }
        do {
            let request = try restoreRequest()
            if result != nil { return }
            // Each scene owns its foreground model/controllers. The installed
            // package registry and canonical discovery remain shared.
            let platform = HanlinScriptingPlatform()
            ownedPlatform = platform
            platform.externalMiniAppOperation = { [weak self] operation, payload in
                guard let self else { throw CancellationError() }
                return try await self.perform(operation, payload: payload)
            }
            self.platform = platform
            let provider = HanlinMiniAppsProvider(platform: platform)
            self.provider = provider
            try await provider.refreshCatalog()
            try Task.checkCancellation()
            guard loadGeneration == generation else { throw CancellationError() }
            guard let item = HanlinMiniAppHost.shared.items.first(where: { $0.id.rawValue == request.appID }) else {
                throw failure("This MiniApp is no longer installed.")
            }
            let input = Self.inputValue(request)
            let launchedView = try await provider.launch(item, includesDismissControl: false,
                sharedInput: input, completeSharedRequest: { [weak self] value in
                    guard let self else { throw CancellationError() }
                    try await self.complete(value)
                })
            try Task.checkCancellation()
            guard loadGeneration == generation else { throw CancellationError() }
            view = launchedView
        } catch {
            ownedPlatform?.dismissActiveApplication()
            guard loadGeneration == generation else { return }
            if error is CancellationError {
                request = nil
                provider = nil
                platform = nil
                return
            }
            self.error = error.localizedDescription
            // A launch failure is an actual error result, not successful output.
            if let request, let mailbox = try? mailbox() {
                let receipt = MiniAppResult(requestID: request.id, status: .error,
                    message: error.localizedDescription)
                do { try mailbox.complete(receipt); result = receipt }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    func perform(_ operation: String, payload: String) async throws -> String {
        guard let request else { throw failure("The shared request is not ready.") }
        switch operation {
        case "miniapps.context":
            return String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        case "miniapps.readAttachment":
            let input = try JSONDecoder().decode([String: String].self, from: Data(payload.utf8))
            guard let rawID = input["id"], let id = UUID(uuidString: rawID) else {
                throw MiniAppBridgeError.invalidAttachment
            }
            let data = try Data(contentsOf: mailbox().attachmentURL(id: id))
            return String(decoding: try JSONEncoder().encode(["base64": data.base64EncodedString()]), as: UTF8.self)
        case "miniapps.writeAttachment":
            let input = try JSONDecoder().decode([String: String].self, from: Data(payload.utf8))
            guard let base64 = input["base64"], let data = Data(base64Encoded: base64) else {
                throw MiniAppBridgeError.invalidAttachment
            }
            let item = try mailbox().writeAttachment(data, name: input["name"], typeIdentifier: input["typeIdentifier"])
            return String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        case "miniapps.complete":
            try await completeJSON(Data(payload.utf8), returnsToSource: false)
            return #"{"ok":true}"#
        case "miniapps.cancel":
            try await finish(MiniAppResult(requestID: request.id, status: .cancelled), returnsToSource: false)
            return #"{"ok":true}"#
        case "miniapps.return":
            await returnToSource()
            releaseEngine()
            return #"{"ok":true}"#
        default:
            throw failure("Unknown MiniApps operation.")
        }
    }

    func done() async {
        guard let request else { return }
        do {
            if result == nil {
                try await finish(MiniAppResult(requestID: request.id, operation: .display))
            } else { await returnToSource() }
        } catch { self.error = error.localizedDescription }
    }

    func close() {
        if result == nil, let request, let mailbox = try? mailbox() {
            let cancelled = MiniAppResult(requestID: request.id, status: .cancelled)
            do { try mailbox.complete(cancelled); result = cancelled }
            catch { self.error = error.localizedDescription }
        }
        loadGeneration = UUID()
        loading = false
        request = nil
        releaseEngine()
    }

    private func releaseEngine() {
        platform?.dismissActiveApplication()
        platform?.externalMiniAppOperation = nil
        view = nil
        provider = nil
        platform = nil
    }

    func cancel() async {
        guard let request else { return }
        do {
            if result == nil {
                try await finish(MiniAppResult(requestID: request.id, status: .cancelled))
            } else {
                await returnToSource()
            }
        } catch { self.error = error.localizedDescription }
    }

    func returnToSource() async {
        guard !returning, let request, let result else { return }
        guard let url = request.callbackURL(for: result) else { return }
        returning = true
        defer { returning = false }
        let opened = await openSource(url)
        if !opened {
            error = Self.localized("The result is saved. Open the source app to continue.",
                                   "התוצאה נשמרה. יש לפתוח את אפליקציית המקור כדי להמשיך.")
        }
    }

    func complete(_ value: HanlinValue) async throws {
        try await completeJSON(value.jsonValue().canonicalJSONData())
    }

    private func completeJSON(_ data: Data, returnsToSource: Bool = true) async throws {
        guard let request else { throw failure("The shared request is not ready.") }
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let receipt: MiniAppResult
        if let text = value as? String {
            receipt = MiniAppResult(requestID: request.id, operation: request.operation,
                items: [.init(kind: .text, text: text, typeIdentifier: "public.utf8-plain-text")])
        } else if var object = value as? [String: Any] {
            // Scripts provide output; the host supplies correlation and origin.
            object["requestID"] = request.id.uuidString
            object["status"] = object["status"] ?? "success"
            object["operation"] = object["operation"] ?? request.operation.rawValue
            object["items"] = object["items"] ?? []
            object["metadata"] = object["metadata"] ?? [:]
            let encoded = try JSONSerialization.data(withJSONObject: object)
            receipt = try JSONDecoder().decode(MiniAppResult.self, from: encoded)
        } else {
            receipt = MiniAppResult(requestID: request.id, operation: .display,
                items: [.init(kind: .json, text: String(decoding: data, as: UTF8.self),
                              typeIdentifier: "public.json")])
        }
        try await finish(receipt, returnsToSource: returnsToSource)
    }

    private func finish(_ receipt: MiniAppResult, returnsToSource: Bool = true) async throws {
        let mailbox = try mailbox()
        if let saved = try mailbox.result(id: requestID) {
            result = saved
        } else {
            try mailbox.complete(receipt)
            result = receipt
        }
        if returnsToSource {
            await returnToSource()
            releaseEngine()
        }
    }

    static func inputValue(_ request: MiniAppInvocation) -> HanlinValue {
        let text = request.inputs.compactMap(\.text).first
            ?? request.source.selection?.text ?? request.source.documentText ?? ""
        return .object([
            "text": .string(text),
            "requestID": .string(request.id.uuidString),
            "operation": .string(request.operation.rawValue),
            "sourceAppID": .string(request.source.appID),
            "documentID": request.source.documentID.map(HanlinValue.string) ?? .null,
            "contextJSON": .string(String(decoding: (try? JSONEncoder().encode(request)) ?? Data(), as: UTF8.self))
        ])
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "HanlinMiniApps.CrossApp", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func localized(_ english: String, _ hebrew: String) -> String {
        Locale.current.language.languageCode?.identifier == "he" ? hebrew : english
    }
}

/// Uses the existing MiniApp view and runtime; contains no substitute engine.
@MainActor
public struct HanlinExternalMiniAppView: View {
    @State private var session: HanlinExternalMiniAppSession

    private let onClose: () -> Void

    public init(requestID: UUID, onClose: @escaping () -> Void = {}) {
        _session = State(initialValue: HanlinExternalMiniAppSession(requestID: requestID))
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let result = session.result {
                    ContentUnavailableView {
                        Label(result.status == .cancelled ? label("Cancelled", "בוטל") : label("Result saved", "התוצאה נשמרה"),
                              systemImage: result.status == .error ? "exclamationmark.circle" : "checkmark.circle")
                    } description: {
                        Text(result.message ?? session.request?.source.displayName ?? "")
                    } actions: {
                        Button(label("Return to source", "חזרה למקור")) {
                            Task { await session.returnToSource() }
                        }
                    }
                } else if let view = session.view {
                    view
                } else if let error = session.error {
                    ContentUnavailableView(label("MiniApp unavailable", "המיני אפליקציה אינה זמינה"),
                                           systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView(label("Opening MiniApp…", "פותח מיני אפליקציה…"))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(session.result == nil ? label("Cancel", "ביטול") : label("Apps", "אפליקציות")) {
                        if session.result != nil { session.close(); onClose() }
                        else { Task { await session.cancel() } }
                    }
                        .disabled(session.returning)
                        .accessibilityIdentifier("miniapps.external.cancel")
                }
                if session.request != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(label("Return", "חזרה")) { Task { await session.done() } }
                            .disabled(session.returning)
                            .accessibilityIdentifier("miniapps.external.return")
                    }
                }
            }
            .navigationTitle(session.request?.source.documentTitle ?? "MiniApps")
            .task { await session.load() }
            .alert(label("MiniApps", "מיני אפליקציות"), isPresented: Binding(
                get: { session.error != nil },
                set: { if !$0 { session.error = nil } }
            )) { Button(label("OK", "אישור")) { session.error = nil } }
              message: { Text(session.error ?? "") }
        }
        .accessibilityIdentifier("miniapps.external.window")
        .onDisappear { session.close() }
    }

    private func label(_ english: String, _ hebrew: String) -> String {
        HanlinExternalMiniAppSession.localized(english, hebrew)
    }
}

@MainActor
enum HanlinExternalMiniAppCatalog {
    static func publish(_ items: [HanlinMiniAppCatalogItem]) throws {
        let projected = items.map { item in
            let symbol: String
            if case .systemSymbol(let name) = item.descriptor.icon { symbol = name }
            else { symbol = "app" }
            return MiniAppCatalogItem(id: item.id.rawValue,
                title: item.descriptor.name.resolved(locale: .current),
                subtitle: item.descriptor.summary.resolved(locale: .current),
                systemImage: symbol,
                supportedOperations: item.id.rawValue == "nativeapp.textstudio"
                    ? [.display, .insert, .replaceSelection, .replaceDocument] : [.display, .custom],
                localizedTitles: item.descriptor.name.values)
        }
        try MiniAppBridgeStore().publishCatalog(projected)
    }
}
