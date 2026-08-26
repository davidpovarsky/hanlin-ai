@preconcurrency import JavaScriptCore
import CoreFoundation
import Foundation
import HanlinPlatformContracts
import HanlinScriptUI

public enum HanlinScriptingEntrypointContext: Equatable, Sendable {
    case application
    case widget(family: String, parameter: String = "")
    case appIntentRegistration
}

public struct HanlinScriptingWidgetPresentation: Equatable, Sendable {
    public let root: HanlinScriptUINode
    public let reloadDate: Date?

    public init(root: HanlinScriptUINode, reloadDate: Date?) {
        self.root = root
        self.reloadDate = reloadDate
    }
}

public struct HanlinScriptingAppIntentRegistration: Equatable, Sendable {
    public let name: String
    public let protocolName: String

    public init(name: String, protocolName: String) {
        self.name = name
        self.protocolName = protocolName
    }
}

@MainActor
public final class HanlinScriptingApplicationSession {
    public let model: HanlinScriptUIModel
    public private(set) var widgetPresentation: HanlinScriptingWidgetPresentation?
    public private(set) var appIntentRegistrations: [HanlinScriptingAppIntentRegistration] = []
    public private(set) var requestedWidgetReload = false

    private let context: JSContext
    private let virtualMachine: JSVirtualMachine
    private let storage: HanlinScriptingPackageStorage
    private let fileSystem: HanlinScriptingPackageFileSystem
    private let filesAllowed: Bool
    private let sqliteStore: HanlinScriptingSQLiteStore
    private let networkAllowed: Bool
    private let networkLoader: HanlinScriptingNetworkLoader
    private let locationAllowed: Bool
    private let locationLoader: HanlinScriptingLocationLoader
    private let healthAllowed: Bool
    private let healthDataAvailable: Bool
    private let healthStatisticsLoader: HanlinScriptingHealthStatisticsLoader
    private let healthActivitySummariesLoader: HanlinScriptingHealthActivitySummariesLoader
    private let healthWorkoutsLoader: HanlinScriptingHealthWorkoutsLoader
    private let notificationsAllowed: Bool
    private let notificationLoader: HanlinScriptingNotificationLoader
    private let remindersAllowed: Bool
    private let reminderLoader: HanlinScriptingReminderLoader
    private let photosAllowed: Bool
    private let assistantAllowed: Bool
    private let assistantLoader: HanlinScriptingAssistantLoader
    private let liveActivityAllowed: Bool
    private let liveActivityLoader: HanlinScriptingLiveActivityLoader
    private let deviceSnapshot: HanlinScriptingDeviceSnapshot
    private let systemLoader: HanlinScriptingSystemLoader
    private let systemUILoader: HanlinScriptingSystemUILoader
    private let imageJPEGEncoder: HanlinScriptingImageJPEGEncoder
    private let entrypointContext: HanlinScriptingEntrypointContext
    private var nativeTasks: [String: Task<Void, Never>] = [:]
    private var appIntentResults: [String: Result<HanlinValue?, any Error>] = [:]
    private var disposed = false

    public init(
        installedPackageID: HanlinInstalledPackageID,
        program: String,
        filename: String,
        entrypointContext: HanlinScriptingEntrypointContext = .application,
        storageAllowed: Bool,
        filesAllowed: Bool = false,
        networkAllowed: Bool = false,
        runtimeRoot: URL? = nil,
        packageSourceDirectory: URL? = nil,
        networkLoader: @escaping HanlinScriptingNetworkLoader = HanlinScriptingURLSessionLoader.load,
        locationAllowed: Bool = false,
        locationLoader: @escaping HanlinScriptingLocationLoader = HanlinScriptingUnavailableLocationLoader.load,
        healthAllowed: Bool = false,
        healthDataAvailable: Bool = false,
        healthStatisticsLoader: @escaping HanlinScriptingHealthStatisticsLoader = HanlinScriptingUnavailableHealthStatisticsLoader.load,
        healthActivitySummariesLoader: @escaping HanlinScriptingHealthActivitySummariesLoader = HanlinScriptingUnavailableHealthActivitySummariesLoader.load,
        healthWorkoutsLoader: @escaping HanlinScriptingHealthWorkoutsLoader = HanlinScriptingUnavailableHealthWorkoutsLoader.load,
        notificationsAllowed: Bool = false,
        notificationLoader: @escaping HanlinScriptingNotificationLoader = HanlinScriptingUnavailableNotificationLoader.load,
        remindersAllowed: Bool = false,
        reminderLoader: @escaping HanlinScriptingReminderLoader = HanlinScriptingUnavailableReminderLoader.load,
        photosAllowed: Bool = false,
        assistantAllowed: Bool = false,
        assistantLoader: @escaping HanlinScriptingAssistantLoader = HanlinScriptingUnavailableAssistantLoader.load,
        liveActivityAllowed: Bool = false,
        liveActivityLoader: @escaping HanlinScriptingLiveActivityLoader = HanlinScriptingUnavailableLiveActivityLoader.load,
        deviceSnapshot: HanlinScriptingDeviceSnapshot = .unavailable,
        systemLoader: @escaping HanlinScriptingSystemLoader = HanlinScriptingUnavailableSystemLoader.load,
        systemUILoader: @escaping HanlinScriptingSystemUILoader = HanlinScriptingUnavailableSystemUILoader.load,
        imageJPEGEncoder: @escaping HanlinScriptingImageJPEGEncoder = HanlinScriptingUnavailableImageJPEGEncoder.encode
    ) throws {
        guard let virtualMachine = JSVirtualMachine(),
              let context = JSContext(virtualMachine: virtualMachine) else {
            throw HanlinScriptingApplicationError.runtimeInitializationFailed
        }
        self.virtualMachine = virtualMachine
        self.context = context
        storage = try HanlinScriptingPackageStorage(
            installedPackageID: installedPackageID,
            allowed: storageAllowed
        )
        fileSystem = try HanlinScriptingPackageFileSystem(
            installedPackageID: installedPackageID.rawValue,
            allowed: filesAllowed,
            runtimeRoot: runtimeRoot,
            packageSourceDirectory: packageSourceDirectory
        )
        self.filesAllowed = filesAllowed
        sqliteStore = HanlinScriptingSQLiteStore(fileSystem: fileSystem)
        self.networkAllowed = networkAllowed
        self.networkLoader = networkLoader
        self.locationAllowed = locationAllowed
        self.locationLoader = locationLoader
        self.healthAllowed = healthAllowed
        self.healthDataAvailable = healthDataAvailable
        self.healthStatisticsLoader = healthStatisticsLoader
        self.healthActivitySummariesLoader = healthActivitySummariesLoader
        self.healthWorkoutsLoader = healthWorkoutsLoader
        self.notificationsAllowed = notificationsAllowed
        self.notificationLoader = notificationLoader
        self.remindersAllowed = remindersAllowed
        self.reminderLoader = reminderLoader
        self.photosAllowed = photosAllowed
        self.assistantAllowed = assistantAllowed
        self.assistantLoader = assistantLoader
        self.liveActivityAllowed = liveActivityAllowed
        self.liveActivityLoader = liveActivityLoader
        self.deviceSnapshot = deviceSnapshot
        self.systemLoader = systemLoader
        self.systemUILoader = systemUILoader
        self.imageJPEGEncoder = imageJPEGEncoder
        self.entrypointContext = entrypointContext

        let router = HanlinScriptingUIEventRouter()
        model = HanlinScriptUIModel(root: .init(kind: .fragment)) { handlerID, payload in
            router.dispatch(handlerID: handlerID, payload: payload)
        }
        router.session = self

        installNativeBridges()
        try evaluate(Self.bootstrap, filename: "hanlin-scripting-ui-runtime.js")
        try evaluate(program, filename: filename)
        switch entrypointContext {
        case .application:
            guard context.objectForKeyedSubscript("__hanlinHasPresentedUI")?.toBool() == true else {
                throw HanlinScriptingApplicationError.missingPresentedUI
            }
        case .widget:
            guard widgetPresentation != nil else {
                throw HanlinScriptingApplicationError.missingWidgetPresentation
            }
        case .appIntentRegistration:
            break
        }
    }

    public func dispatch(handlerID: String, payload: HanlinValue) {
        guard !disposed,
              let payloadJSON = try? payload.jsonValue(destination: .javaScriptBinary64).canonicalJSONData(),
              let payloadString = String(data: payloadJSON, encoding: .utf8),
              let handlerLiteral = Self.javaScriptLiteral(handlerID),
              let payloadLiteral = Self.javaScriptLiteral(payloadString) else { return }
        do {
            try evaluate(
                "globalThis.__hanlinDispatch(\(handlerLiteral), \(payloadLiteral));",
                filename: "hanlin-event.js"
            )
        } catch {
            // Runtime errors remain contained to this package session. The UI keeps
            // its last valid tree rather than replacing it with an unsafe partial tree.
        }
    }

    public func invokeAppIntent(name: String, parameters: HanlinValue) async throws -> HanlinValue? {
        guard case .appIntentRegistration = entrypointContext,
              appIntentRegistrations.contains(where: { $0.name == name }),
              let parametersData = try? parameters.jsonValue(destination: .javaScriptBinary64).canonicalJSONData(),
              let parametersJSON = String(data: parametersData, encoding: .utf8),
              let nameLiteral = Self.javaScriptLiteral(name),
              let parametersLiteral = Self.javaScriptLiteral(parametersJSON) else {
            throw HanlinScriptingApplicationError.unknownAppIntent
        }
        let requestID = UUID().uuidString.lowercased()
        guard let requestLiteral = Self.javaScriptLiteral(requestID) else {
            throw HanlinScriptingApplicationError.unknownAppIntent
        }
        try evaluate(
            "globalThis.__hanlinInvokeAppIntent(\(requestLiteral), \(nameLiteral), \(parametersLiteral));",
            filename: "hanlin-app-intent.js"
        )
        await waitForNativeQuiescence()
        try evaluate("void 0;", filename: "hanlin-app-intent-quiescence.js")
        guard let result = appIntentResults.removeValue(forKey: requestID) else {
            throw HanlinScriptingApplicationError.appIntentDidNotComplete
        }
        return try result.get()
    }

    func waitForNativeQuiescence() async {
        var consecutiveIdleDrains = 0
        while consecutiveIdleDrains < 3 {
            while let task = nativeTasks.values.first {
                await task.value
            }
            try? evaluate("void 0;", filename: "hanlin-native-quiescence.js")
            if nativeTasks.isEmpty {
                consecutiveIdleDrains += 1
                await Task.yield()
            } else {
                consecutiveIdleDrains = 0
            }
        }
    }

    public func dismiss() {
        guard !disposed else { return }
        context.evaluateScript("globalThis.__hanlinDismiss?.();")
        dispose()
    }

    public func dispose() {
        guard !disposed else { return }
        disposed = true
        context.evaluateScript("globalThis.__hanlinDispose?.();")
        nativeTasks.values.forEach { $0.cancel() }
        nativeTasks.removeAll(keepingCapacity: false)
        appIntentResults.removeAll(keepingCapacity: false)
        fileSystem.stopAccessingExternalURLs()
        context.exceptionHandler = nil
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeRender" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageGet" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageSet" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageClear" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageRemove" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageContains" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageKeys" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageGetData" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeStorageSetData" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeFileInfo" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeFileSync" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeImageJPEG" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeAsync" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeAssistantAvailable" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeAssistantStart" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinCancelNative" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeDeviceSnapshot" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeHealthDataAvailable" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeWidgetPresent" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeWidgetReloadAll" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeAppIntentRegister" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeAppIntentComplete" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeEntrypointKind" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeWidgetFamily" as NSString)
        context.setObject(nil, forKeyedSubscript: "__hanlinNativeWidgetParameter" as NSString)
    }

    private func installNativeBridges() {
        let render: @convention(block) (String) -> Void = { [weak self] json in
            guard let self, !self.disposed,
                  json.utf8.count <= 1_048_576,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let node = try? Self.decodeNode(object, depth: 0) else { return }
            try? self.model.apply(.render(node))
        }
        let storageGet: @convention(block) (String, Bool) -> String = { [storage] key, shared in
            storage.response(for: key, shared: shared)
        }
        let storageSet: @convention(block) (String, String, Bool) -> Bool = {
            [storage] key, json, shared in
            storage.set(json: json, for: key, shared: shared)
        }
        let storageClear: @convention(block) () -> Bool = { [storage] in storage.clear() }
        let storageRemove: @convention(block) (String, Bool) -> Bool = { [storage] key, shared in
            storage.remove(key: key, shared: shared)
        }
        let storageContains: @convention(block) (String, Bool) -> Bool = { [storage] key, shared in
            storage.contains(key: key, shared: shared)
        }
        let storageKeys: @convention(block) (Bool) -> String = { [storage] shared in
            storage.keysResponse(shared: shared)
        }
        let storageGetData: @convention(block) (String, Bool) -> String = { [storage] key, shared in
            storage.dataResponse(for: key, shared: shared)
        }
        let storageSetData: @convention(block) (String, String, Bool) -> Bool = {
            [storage] key, base64, shared in
            storage.setData(base64: base64, for: key, shared: shared)
        }
        let fileInfo: @convention(block) () -> String = { [fileSystem] in
            HanlinScriptingNativeJSON.success(fileSystem.publicDirectories)
        }
        let fileSync: @convention(block) (String, String) -> String = { [fileSystem] operation, json in
            do {
                let payload = try HanlinScriptingNativeJSON.decodeObject(json)
                return HanlinScriptingNativeJSON.success(
                    try fileSystem.perform(operation: operation, payload: payload)
                )
            } catch {
                return HanlinScriptingNativeJSON.failure(error)
            }
        }
        let nativeAsync: @convention(block) (String, String, String) -> Void = {
            [weak self] requestID, operation, json in
            self?.enqueueNativeRequest(id: requestID, operation: operation, payloadJSON: json)
        }
        let imageJPEG: @convention(block) (String, Double) -> String = {
            [imageJPEGEncoder] base64, quality in
            do {
                guard quality.isFinite, (0 ... 1).contains(quality),
                      let data = Data(base64Encoded: base64), !data.isEmpty,
                      data.count <= 64 * 1_024 * 1_024 else {
                    throw HanlinScriptingNativeError(
                        name: "TypeError", code: "invalid_image",
                        message: "The image or compression quality is invalid."
                    )
                }
                let encoded = try imageJPEGEncoder(data, quality)
                guard !encoded.isEmpty, encoded.count <= 64 * 1_024 * 1_024 else {
                    throw HanlinScriptingNativeError(
                        name: "Error", code: "image_encoding_failed",
                        message: "The image could not be encoded as JPEG."
                    )
                }
                return HanlinScriptingNativeJSON.success(encoded.base64EncodedString())
            } catch {
                return HanlinScriptingNativeJSON.failure(error)
            }
        }
        let assistantStart: @convention(block) (String, String) -> Void = {
            [weak self] requestID, json in
            self?.enqueueAssistantRequest(id: requestID, payloadJSON: json)
        }
        let cancelNative: @convention(block) (String) -> Void = { [weak self] requestID in
            self?.nativeTasks[requestID]?.cancel()
        }
        let widgetPresent: @convention(block) (String) -> Bool = { [weak self] json in
            guard let self, !self.disposed, json.utf8.count <= 1_048_576,
                  case .widget = self.entrypointContext,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rootObject = object["root"],
                  let root = try? Self.decodeNode(rootObject, depth: 0) else { return false }
            let milliseconds = (object["reloadDate"] as? NSNumber)?.doubleValue
            self.widgetPresentation = .init(
                root: root,
                reloadDate: milliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) }
            )
            return true
        }
        let widgetReloadAll: @convention(block) () -> Void = { [weak self] in
            self?.requestedWidgetReload = true
        }
        let appIntentRegister: @convention(block) (String) -> Bool = { [weak self] json in
            guard let self, !self.disposed,
                  case .appIntentRegistration = self.entrypointContext,
                  json.utf8.count <= 16_384,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["name"] as? String,
                  let protocolName = object["protocol"] as? String,
                  !name.isEmpty, name.utf8.count <= 256,
                  !protocolName.isEmpty, protocolName.utf8.count <= 128,
                  !self.appIntentRegistrations.contains(where: { $0.name == name }) else { return false }
            self.appIntentRegistrations.append(.init(name: name, protocolName: protocolName))
            return true
        }
        let appIntentComplete: @convention(block) (String, Bool, String) -> Void = {
            [weak self] requestID, succeeded, json in
            guard let self, !self.disposed, requestID.utf8.count <= 128,
                  self.appIntentResults[requestID] == nil else { return }
            if succeeded {
                guard json.utf8.count <= 1_048_576,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let value = try? Self.bridgeValue(object, depth: 0) else {
                    self.appIntentResults[requestID] = .failure(HanlinScriptingApplicationError.invalidAppIntentResult)
                    return
                }
                self.appIntentResults[requestID] = .success(value)
            } else {
                self.appIntentResults[requestID] = .failure(
                    HanlinScriptingApplicationError.appIntentFailed(String(json.prefix(512)))
                )
            }
        }
        context.setObject(render, forKeyedSubscript: "__hanlinNativeRender" as NSString)
        context.setObject(storageGet, forKeyedSubscript: "__hanlinNativeStorageGet" as NSString)
        context.setObject(storageSet, forKeyedSubscript: "__hanlinNativeStorageSet" as NSString)
        context.setObject(storageClear, forKeyedSubscript: "__hanlinNativeStorageClear" as NSString)
        context.setObject(storageRemove, forKeyedSubscript: "__hanlinNativeStorageRemove" as NSString)
        context.setObject(storageContains, forKeyedSubscript: "__hanlinNativeStorageContains" as NSString)
        context.setObject(storageKeys, forKeyedSubscript: "__hanlinNativeStorageKeys" as NSString)
        context.setObject(storageGetData, forKeyedSubscript: "__hanlinNativeStorageGetData" as NSString)
        context.setObject(storageSetData, forKeyedSubscript: "__hanlinNativeStorageSetData" as NSString)
        context.setObject(fileInfo, forKeyedSubscript: "__hanlinNativeFileInfo" as NSString)
        context.setObject(fileSync, forKeyedSubscript: "__hanlinNativeFileSync" as NSString)
        context.setObject(imageJPEG, forKeyedSubscript: "__hanlinNativeImageJPEG" as NSString)
        context.setObject(nativeAsync, forKeyedSubscript: "__hanlinNativeAsync" as NSString)
        context.setObject(
            assistantAllowed,
            forKeyedSubscript: "__hanlinNativeAssistantAvailable" as NSString
        )
        context.setObject(assistantStart, forKeyedSubscript: "__hanlinNativeAssistantStart" as NSString)
        context.setObject(cancelNative, forKeyedSubscript: "__hanlinCancelNative" as NSString)
        context.setObject(
            deviceSnapshot.nativeObject,
            forKeyedSubscript: "__hanlinNativeDeviceSnapshot" as NSString
        )
        context.setObject(
            healthAllowed && healthDataAvailable,
            forKeyedSubscript: "__hanlinNativeHealthDataAvailable" as NSString
        )
        context.setObject(widgetPresent, forKeyedSubscript: "__hanlinNativeWidgetPresent" as NSString)
        context.setObject(widgetReloadAll, forKeyedSubscript: "__hanlinNativeWidgetReloadAll" as NSString)
        context.setObject(appIntentRegister, forKeyedSubscript: "__hanlinNativeAppIntentRegister" as NSString)
        context.setObject(appIntentComplete, forKeyedSubscript: "__hanlinNativeAppIntentComplete" as NSString)
        switch entrypointContext {
        case .application:
            context.setObject("application", forKeyedSubscript: "__hanlinNativeEntrypointKind" as NSString)
        case let .widget(family, parameter):
            context.setObject("widget", forKeyedSubscript: "__hanlinNativeEntrypointKind" as NSString)
            context.setObject(family, forKeyedSubscript: "__hanlinNativeWidgetFamily" as NSString)
            context.setObject(parameter, forKeyedSubscript: "__hanlinNativeWidgetParameter" as NSString)
        case .appIntentRegistration:
            context.setObject("appIntent", forKeyedSubscript: "__hanlinNativeEntrypointKind" as NSString)
        }
    }

    private func enqueueAssistantRequest(id: String, payloadJSON: String) {
        guard !disposed, assistantAllowed, !id.isEmpty, id.utf8.count <= 128,
              nativeTasks[id] == nil else {
            resolveAssistantRequest(
                id: id,
                resultJSON: HanlinScriptingNativeJSON.failure(HanlinScriptingNativeError(
                    name: "Error",
                    code: assistantAllowed ? "invalid_request" : "permission_denied",
                    message: assistantAllowed
                        ? "The Assistant request could not be started."
                        : "The Assistant capability is not granted."
                ))
            )
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let request = try HanlinScriptingAssistantPayloadDecoder.decode(payloadJSON)
                let stream = try await assistantLoader(request)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    resolveAssistantRequest(
                        id: id,
                        resultJSON: HanlinScriptingNativeJSON.success(try chunk.nativeObject())
                    )
                }
                try Task.checkCancellation()
                resolveAssistantRequest(id: id, resultJSON: HanlinScriptingNativeJSON.success(NSNull()))
            } catch is CancellationError {
                resolveAssistantRequest(
                    id: id,
                    resultJSON: HanlinScriptingNativeJSON.failure(HanlinScriptingNativeError(
                        name: "AbortError",
                        code: "cancelled",
                        message: "The Assistant request was cancelled."
                    ))
                )
            } catch {
                resolveAssistantRequest(id: id, resultJSON: HanlinScriptingNativeJSON.failure(error))
            }
            nativeTasks[id] = nil
        }
        nativeTasks[id] = task
    }

    private func enqueueNativeRequest(id: String, operation: String, payloadJSON: String) {
        guard !disposed, !id.isEmpty, id.utf8.count <= 128, nativeTasks[id] == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result: String
            do {
                let value = try await performNativeRequest(
                    operation: operation,
                    payloadJSON: payloadJSON
                )
                try Task.checkCancellation()
                result = value
            } catch is CancellationError {
                result = HanlinScriptingNativeJSON.failure(HanlinScriptingNativeError(
                    name: "AbortError",
                    code: "cancelled",
                    message: "The operation was cancelled."
                ))
            } catch {
                result = HanlinScriptingNativeJSON.failure(error)
            }
            nativeTasks[id] = nil
            guard !disposed else { return }
            resolveNativeRequest(id: id, resultJSON: result)
        }
        nativeTasks[id] = task
    }

    private func performNativeRequest(operation: String, payloadJSON: String) async throws -> String {
        if operation == "runtime.delay" {
            let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
            guard let milliseconds = payload["milliseconds"] as? NSNumber,
                  milliseconds.doubleValue.isFinite,
                  milliseconds.doubleValue >= 0,
                  milliseconds.doubleValue <= 300_000 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_delay",
                    message: "The delay must be between 0 and 300000 milliseconds."
                )
            }
            let delay = Int64(milliseconds.doubleValue.rounded(.up))
            try await Task.sleep(for: .milliseconds(delay))
            return HanlinScriptingNativeJSON.success(NSNull())
        }
        if operation.hasPrefix("file.") {
            let fileSystem = fileSystem
            return await Task.detached(priority: .userInitiated) {
                do {
                    let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
                    return HanlinScriptingNativeJSON.success(
                        try fileSystem.perform(operation: operation, payload: payload)
                    )
                } catch {
                    return HanlinScriptingNativeJSON.failure(error)
                }
            }.value
        }
        if operation.hasPrefix("sqlite.") {
            let sqliteStore = sqliteStore
            return await Task.detached(priority: .userInitiated) {
                do {
                    return HanlinScriptingNativeJSON.success(
                        try sqliteStore.perform(operation: operation, payloadJSON: payloadJSON)
                    )
                } catch {
                    return HanlinScriptingNativeJSON.failure(error)
                }
            }.value
        }
        if operation == "network.fetch" {
            guard networkAllowed else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "permission_denied",
                    message: "The network capability is not granted."
                )
            }
            guard let data = payloadJSON.data(using: .utf8) else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_payload",
                    message: "The native request payload is invalid."
                )
            }
            let request = try JSONDecoder().decode(HanlinScriptingFetchRequest.self, from: data)
            let response = try await networkLoader(request)
            return HanlinScriptingNativeJSON.success([
                "url": response.url,
                "status": response.status,
                "headers": response.headers,
                "bodyBase64": response.body.base64EncodedString(),
            ])
        }
        if operation.hasPrefix("pasteboard.") || operation == "safari.openURL" {
            return HanlinScriptingNativeJSON.success(
                try await systemLoader(operation, payloadJSON).nativeObject
            )
        }
        if operation.hasPrefix("documentPicker.") || operation.hasPrefix("quickLook.") {
            guard filesAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error", code: "permission_denied",
                    message: "The files capability is not granted."
                )
            }
            let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
            switch operation {
            case "documentPicker.pickFiles":
                let multiple = try Self.optionalBoolean(payload["allowsMultipleSelection"], name: "allowsMultipleSelection") ?? false
                let extensions = try Self.optionalBoolean(payload["shouldShowFileExtensions"], name: "shouldShowFileExtensions") ?? true
                let types = try Self.boundedStrings(payload["types"], maximumCount: 64, maximumBytes: 256)
                guard case let .urls(urls) = try await systemUILoader(.pickFiles(
                    allowsMultipleSelection: multiple,
                    shouldShowFileExtensions: extensions,
                    contentTypeIdentifiers: types
                )) else { throw Self.invalidSystemUIResult() }
                return HanlinScriptingNativeJSON.success(try fileSystem.grantExternalURLs(urls))
            case "documentPicker.pickDirectory":
                guard case let .urls(urls) = try await systemUILoader(.pickDirectory) else {
                    throw Self.invalidSystemUIResult()
                }
                let paths = try fileSystem.grantExternalURLs(Array(urls.prefix(1)))
                return HanlinScriptingNativeJSON.success(paths.first.map { $0 as Any } ?? NSNull())
            case "documentPicker.stopAccessingSecurityScopedResources":
                fileSystem.stopAccessingExternalURLs()
                return HanlinScriptingNativeJSON.success(NSNull())
            case "quickLook.previewURLs":
                let paths = try Self.boundedStrings(payload["urls"], maximumCount: 128, maximumBytes: 8_192)
                guard !paths.isEmpty else { throw Self.invalidSystemUIRequest("QuickLook requires at least one URL.") }
                let urls = try paths.map(fileSystem.previewURL(for:))
                guard case .completed = try await systemUILoader(.previewURLs(urls)) else {
                    throw Self.invalidSystemUIResult()
                }
                return HanlinScriptingNativeJSON.success(NSNull())
            case "quickLook.previewText":
                guard let text = payload["text"] as? String,
                      text.utf8.count <= 4 * 1_024 * 1_024 else {
                    throw Self.invalidSystemUIRequest("QuickLook preview text is invalid or too large.")
                }
                guard case .completed = try await systemUILoader(.previewText(text)) else {
                    throw Self.invalidSystemUIResult()
                }
                return HanlinScriptingNativeJSON.success(NSNull())
            case "quickLook.previewImage":
                guard let base64 = payload["base64"] as? String,
                      base64.utf8.count <= 96 * 1_024 * 1_024,
                      let data = Data(base64Encoded: base64), !data.isEmpty,
                      data.count <= 64 * 1_024 * 1_024 else {
                    throw Self.invalidSystemUIRequest("QuickLook preview image is invalid or too large.")
                }
                guard case .completed = try await systemUILoader(.previewImage(data)) else {
                    throw Self.invalidSystemUIResult()
                }
                return HanlinScriptingNativeJSON.success(NSNull())
            default:
                throw Self.invalidSystemUIRequest("The requested system UI operation is unavailable.")
            }
        }
        if operation.hasPrefix("photos.") {
            guard photosAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error", code: "permission_denied",
                    message: "The Photos capability is not granted."
                )
            }
            let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
            switch operation {
            case "photos.pickPhotos":
                guard let number = payload["count"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite,
                      number.doubleValue.rounded(.towardZero) == number.doubleValue,
                      (1 ... 100).contains(number.intValue) else {
                    throw Self.invalidPhotosRequest("Photos.pickPhotos count must be an integer from 1 through 100.")
                }
                guard case let .images(images) = try await systemUILoader(.pickPhotos(limit: number.intValue)) else {
                    throw Self.invalidSystemUIResult()
                }
                return HanlinScriptingNativeJSON.success(images.map { $0.base64EncodedString() })
            case "photos.takePhoto":
                guard payload.isEmpty else {
                    throw Self.invalidPhotosRequest("Photos.takePhoto does not accept options.")
                }
                guard case let .image(image) = try await systemUILoader(.takePhoto) else {
                    throw Self.invalidSystemUIResult()
                }
                return HanlinScriptingNativeJSON.success(image?.base64EncodedString() ?? NSNull())
            default:
                throw Self.invalidPhotosRequest("The requested Photos operation is unavailable.")
            }
        }
        if operation.hasPrefix("dialog.") {
            let actionName = String(operation.dropFirst("dialog.".count))
            guard let kind = HanlinScriptingDialogKind(rawValue: actionName) else {
                throw Self.invalidDialogRequest("The requested Dialog operation is unavailable.")
            }
            let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
            let title = try Self.dialogString(payload["title"], name: "title", maximumBytes: 4_096)
            let message = try Self.dialogString(payload["message"], name: "message", maximumBytes: 64 * 1_024)
            let confirmLabel = try Self.dialogString(
                payload["confirmLabel"] ?? payload["buttonLabel"],
                name: "confirmLabel", maximumBytes: 512
            )
            let cancelLabel = try Self.dialogString(payload["cancelLabel"], name: "cancelLabel", maximumBytes: 512)
            let defaultValue = try Self.dialogString(payload["defaultValue"], name: "defaultValue", maximumBytes: 64 * 1_024)
            let placeholder = try Self.dialogString(payload["placeholder"], name: "placeholder", maximumBytes: 4_096)
            let keyboardType = try Self.dialogString(payload["keyboardType"], name: "keyboardType", maximumBytes: 128)
            let obscureText = try Self.dialogBoolean(payload["obscureText"], name: "obscureText") ?? false
            let selectAll = try Self.dialogBoolean(payload["selectAll"], name: "selectAll") ?? false
            let cancelButton = try Self.dialogBoolean(payload["cancelButton"], name: "cancelButton") ?? true
            var actions: [HanlinScriptingDialogAction] = []
            if let actionValues = payload["actions"] {
                guard let actionValues = actionValues as? [Any], actionValues.count <= 64 else {
                    throw Self.invalidDialogRequest("Dialog actions are invalid or too numerous.")
                }
                actions = try actionValues.map { value in
                    guard let value = value as? [String: Any],
                          let label = try Self.dialogString(value["label"], name: "action label", maximumBytes: 512),
                          !label.isEmpty else {
                        throw Self.invalidDialogRequest("Every Dialog action requires a label.")
                    }
                    return .init(
                        label: label,
                        destructive: try Self.dialogBoolean(value["destructive"], name: "destructive") ?? false
                    )
                }
            }
            switch kind {
            case .alert:
                guard message != nil else { throw Self.invalidDialogRequest("Dialog.alert requires a message.") }
            case .confirm:
                guard message != nil else { throw Self.invalidDialogRequest("Dialog.confirm requires a message.") }
            case .prompt:
                guard title != nil else { throw Self.invalidDialogRequest("Dialog.prompt requires a title.") }
            case .actionSheet:
                guard title != nil, !actions.isEmpty else {
                    throw Self.invalidDialogRequest("Dialog.actionSheet requires a title and at least one action.")
                }
            }
            let result = try await systemUILoader(.dialog(.init(
                kind: kind,
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                defaultValue: defaultValue,
                placeholder: placeholder,
                obscureText: obscureText,
                selectAll: selectAll,
                keyboardType: keyboardType,
                cancelButton: cancelButton,
                actions: actions
            )))
            switch (kind, result) {
            case (.alert, .completed):
                return HanlinScriptingNativeJSON.success(NSNull())
            case let (.confirm, .boolean(value)):
                return HanlinScriptingNativeJSON.success(value)
            case let (.prompt, .text(value)):
                return HanlinScriptingNativeJSON.success(value ?? NSNull())
            case let (.actionSheet, .index(value)):
                return HanlinScriptingNativeJSON.success(value.map { $0 as Any } ?? NSNull())
            default:
                throw Self.invalidSystemUIResult()
            }
        }
        if operation == "editor.present" {
            let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
            guard let content = payload["content"] as? String,
                  content.utf8.count <= 4 * 1_024 * 1_024,
                  let fileExtension = payload["ext"] as? String,
                  Self.editorExtensions.contains(fileExtension) else {
                throw Self.invalidEditorRequest("Editor content or extension is invalid.")
            }
            let readOnly = try Self.editorBoolean(payload["readOnly"], name: "readOnly") ?? false
            let fullscreen = try Self.editorBoolean(payload["fullscreen"], name: "fullscreen") ?? false
            let navigationTitle = try Self.dialogString(
                payload["navigationTitle"], name: "navigationTitle", maximumBytes: 4_096
            )
            guard case let .text(result) = try await systemUILoader(.editor(.init(
                content: content,
                fileExtension: fileExtension,
                readOnly: readOnly,
                navigationTitle: navigationTitle,
                fullscreen: fullscreen
            ))), let result else {
                throw Self.invalidSystemUIResult()
            }
            guard result.utf8.count <= 4 * 1_024 * 1_024 else {
                throw Self.invalidEditorRequest("The edited content is too large.")
            }
            return HanlinScriptingNativeJSON.success(result)
        }
        if operation.hasPrefix("location.") {
            guard locationAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "permission_denied",
                    message: "The Location capability is not granted."
                )
            }
            let request = try HanlinScriptingLocationPayloadDecoder.decode(
                operation: operation,
                json: payloadJSON
            )
            let result = try await locationLoader(request)
            return HanlinScriptingNativeJSON.success(result.nativeObject)
        }
        if operation == "health.queryStatistics" {
            guard healthAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "permission_denied",
                    message: "The Health capability is not granted."
                )
            }
            guard healthDataAvailable else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "health_unavailable",
                    message: "Health data is unavailable on this device."
                )
            }
            let request = try HanlinScriptingHealthPayloadDecoder.decodeStatistics(payloadJSON)
            let result = try await healthStatisticsLoader(request)
            return HanlinScriptingNativeJSON.success(result?.nativeObject ?? NSNull())
        }
        if operation == "health.queryActivitySummaries" {
            try ensureHealthAvailable()
            let request = try HanlinScriptingHealthPayloadDecoder.decodeActivitySummaries(payloadJSON)
            let results = try await healthActivitySummariesLoader(request)
            return HanlinScriptingNativeJSON.success(results.map(\.nativeObject))
        }
        if operation == "health.queryWorkouts" {
            try ensureHealthAvailable()
            let request = try HanlinScriptingHealthPayloadDecoder.decodeWorkouts(payloadJSON)
            let results = try await healthWorkoutsLoader(request)
            return HanlinScriptingNativeJSON.success(results.map(\.nativeObject))
        }
        if operation.hasPrefix("notification.") {
            guard notificationsAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "permission_denied",
                    message: "The Notifications capability is not granted."
                )
            }
            let request = try HanlinScriptingNotificationPayloadDecoder.decode(
                operation: operation,
                json: payloadJSON
            )
            return HanlinScriptingNativeJSON.success(try await notificationLoader(request))
        }
        if operation.hasPrefix("reminder.") {
            guard remindersAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "permission_denied",
                    message: "The Reminders capability is not granted."
                )
            }
            let request = try HanlinScriptingReminderPayloadDecoder.decode(
                operation: operation,
                json: payloadJSON
            )
            return HanlinScriptingNativeJSON.success(try await reminderLoader(request))
        }
        if operation.hasPrefix("liveActivity.") {
            guard liveActivityAllowed else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "permission_denied",
                    message: "Live Activities are not available for this package."
                )
            }
            let payload = try HanlinScriptingNativeJSON.decodeObject(payloadJSON)
            let actionName = String(operation.dropFirst("liveActivity.".count))
                .replacingOccurrences(of: "areActivitiesEnabled", with: "are_activities_enabled")
            guard let action = HanlinScriptingLiveActivityAction(rawValue: actionName) else {
                throw HanlinScriptingNativeError(
                    name: "Error", code: "unsupported_operation",
                    message: "The Live Activity operation is unavailable."
                )
            }
            let name = payload["name"] as? String
            let activityID = payload["activityId"] as? String
            guard name?.utf8.count ?? 0 <= 256, activityID?.utf8.count ?? 0 <= 256 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError", code: "invalid_payload",
                    message: "The Live Activity identifier is too large."
                )
            }
            let stateJSON: Data? = try payload["state"].map { state in
                guard JSONSerialization.isValidJSONObject(state) else {
                    throw HanlinScriptingNativeError(
                        name: "TypeError", code: "invalid_payload",
                        message: "The Live Activity state must be a JSON object or array."
                    )
                }
                let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
                guard data.count <= 1_048_576 else {
                    throw HanlinScriptingNativeError(
                        name: "TypeError", code: "invalid_payload",
                        message: "The Live Activity state is too large."
                    )
                }
                return data
            }
            let root = try payload["root"].map { try Self.decodeNode($0, depth: 0) }
            let options = payload["options"] as? [String: Any] ?? [:]
            let staleMilliseconds = (options["staleDate"] as? NSNumber)?.doubleValue
            let relevanceScore = (options["relevanceScore"] as? NSNumber)?.doubleValue
            let dismissTimeInterval = (options["dismissTimeInterval"] as? NSNumber)?.doubleValue
            for value in [staleMilliseconds, relevanceScore, dismissTimeInterval].compactMap({ $0 }) {
                guard value.isFinite else {
                    throw HanlinScriptingNativeError(
                        name: "TypeError", code: "invalid_payload",
                        message: "Live Activity options must be finite numbers."
                    )
                }
            }
            let result = try await liveActivityLoader(.init(
                action: action,
                name: name,
                activityID: activityID,
                stateJSON: stateJSON,
                root: root,
                staleDate: staleMilliseconds.map { Date(timeIntervalSince1970: $0 / 1_000) },
                relevanceScore: relevanceScore,
                dismissTimeInterval: dismissTimeInterval
            ))
            return HanlinScriptingNativeJSON.success(result.nativeObject())
        }
        throw HanlinScriptingNativeError(
            name: "Error",
            code: "unsupported_operation",
            message: "The requested native operation is unavailable."
        )
    }

    private func ensureHealthAvailable() throws {
        guard healthAllowed else {
            throw HanlinScriptingNativeError(
                name: "Error", code: "permission_denied",
                message: "The Health capability is not granted."
            )
        }
        guard healthDataAvailable else {
            throw HanlinScriptingNativeError(
                name: "Error", code: "health_unavailable",
                message: "Health data is unavailable on this device."
            )
        }
    }

    private static func optionalBoolean(_ value: Any?, name: String) throws -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw invalidSystemUIRequest("DocumentPicker \(name) must be a Boolean.")
        }
        return number.boolValue
    }

    private static func boundedStrings(
        _ value: Any?,
        maximumCount: Int,
        maximumBytes: Int
    ) throws -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        guard let values = value as? [Any], values.count <= maximumCount else {
            throw invalidSystemUIRequest("The system UI string list is invalid.")
        }
        return try values.map { value in
            guard let string = value as? String,
                  !string.isEmpty, string.utf8.count <= maximumBytes else {
                throw invalidSystemUIRequest("A system UI string value is invalid.")
            }
            return string
        }
    }

    private static func invalidSystemUIRequest(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_system_ui_request", message: message)
    }

    private static func invalidPhotosRequest(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_photos_request", message: message)
    }

    private static func dialogString(
        _ value: Any?, name: String, maximumBytes: Int
    ) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String, string.utf8.count <= maximumBytes,
              !string.contains("\0") else {
            throw invalidDialogRequest("Dialog \(name) is invalid or too large.")
        }
        return string
    }

    private static func dialogBoolean(_ value: Any?, name: String) throws -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw invalidDialogRequest("Dialog \(name) must be a Boolean.")
        }
        return number.boolValue
    }

    private static func invalidDialogRequest(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_dialog_request", message: message)
    }

    private static let editorExtensions: Set<String> = [
        "tsx", "ts", "js", "jsx", "txt", "md", "css", "html", "json",
    ]

    private static func editorBoolean(_ value: Any?, name: String) throws -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw invalidEditorRequest("Editor \(name) must be a Boolean.")
        }
        return number.boolValue
    }

    private static func invalidEditorRequest(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_editor_request", message: message)
    }

    private static func invalidSystemUIResult() -> HanlinScriptingNativeError {
        .init(name: "Error", code: "invalid_system_ui_result", message: "The system UI returned an invalid result.")
    }

    private func resolveNativeRequest(id: String, resultJSON: String) {
        guard let function = context.objectForKeyedSubscript("__hanlinResolveNative"),
              !function.isUndefined else { return }
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        function.call(withArguments: [id, resultJSON])
        context.exceptionHandler = nil
        if exception != nil {
            nativeTasks[id]?.cancel()
        }
    }

    private func resolveAssistantRequest(id: String, resultJSON: String) {
        guard !disposed,
              let function = context.objectForKeyedSubscript("__hanlinAssistantReceive"),
              !function.isUndefined else { return }
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        function.call(withArguments: [id, resultJSON])
        context.exceptionHandler = nil
        if exception != nil { nativeTasks[id]?.cancel() }
    }

    private func evaluate(_ source: String, filename: String) throws {
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        context.evaluateScript(
            source,
            withSourceURL: URL(string: "hanlin-package:///\(filename)")
        )
        context.exceptionHandler = nil
        if let exception {
            let message = exception.toString() ?? "script_failure"
            throw HanlinScriptingApplicationError.evaluationFailed(String(message.prefix(512)))
        }
    }

    private static func decodeNode(_ value: Any, depth: Int) throws -> HanlinScriptUINode {
        guard depth <= 128,
              let object = value as? [String: Any],
              let kindName = object["kind"] as? String,
              let kind = HanlinScriptUIPrimitive(rawValue: kindName) else {
            throw HanlinScriptingApplicationError.invalidUITree
        }
        let properties = try (object["properties"] as? [String: Any] ?? [:]).mapValues {
            try bridgeValue($0, depth: depth + 1)
        }
        let children = try (object["children"] as? [Any] ?? []).map {
            try decodeNode($0, depth: depth + 1)
        }
        return .init(
            kind: kind,
            key: object["key"] as? String,
            properties: properties,
            children: children
        )
    }

    private static func bridgeValue(_ value: Any, depth: Int) throws -> HanlinValue {
        guard depth <= 128 else { throw HanlinScriptingApplicationError.invalidUITree }
        switch value {
        case is NSNull:
            return .null
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            let double = value.doubleValue
            if double.rounded(.towardZero) == double,
               double >= Double(Int64.min), double <= Double(Int64.max) {
                return .integer(value.int64Value)
            }
            return try .finiteNumber(double)
        case let value as [Any]:
            return .array(try value.map { try bridgeValue($0, depth: depth + 1) })
        case let value as [String: Any]:
            return .object(try HanlinObject(uniqueMembers: value.map {
                (key: $0.key, value: try bridgeValue($0.value, depth: depth + 1))
            }))
        default:
            throw HanlinScriptingApplicationError.invalidUITree
        }
    }

    private static func javaScriptLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
private final class HanlinScriptingUIEventRouter {
    weak var session: HanlinScriptingApplicationSession?

    func dispatch(handlerID: String, payload: HanlinValue) {
        session?.dispatch(handlerID: handlerID, payload: payload)
    }
}

private final class HanlinScriptingPackageStorage: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let suiteName: String
    private let allowed: Bool
    private let maximumBytes = 1_048_576
    private let dataPrefix = "__hanlin_data__:"

    init(installedPackageID: HanlinInstalledPackageID, allowed: Bool) throws {
        let suiteName = "com.hanlin.scripting.storage.\(installedPackageID.rawValue)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HanlinScriptingApplicationError.storageInitializationFailed
        }
        self.defaults = defaults
        self.suiteName = suiteName
        self.allowed = allowed
    }

    func response(for key: String, shared: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared, Self.valid(key: key) else { return #"{"allowed":false}"# }
        guard let json = defaults.string(forKey: key) else { return #"{"allowed":true,"found":false}"# }
        guard let encoded = try? JSONEncoder().encode(json),
              let literal = String(data: encoded, encoding: .utf8) else {
            return #"{"allowed":true,"found":false}"#
        }
        return #"{"allowed":true,"found":true,"json":\#(literal)}"#
    }

    func set(json: String, for key: String, shared: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared, Self.valid(key: key), json.utf8.count <= maximumBytes,
              let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
            return false
        }
        let existingValues = defaults.persistentDomain(forName: suiteName) ?? [:]
        let existingBytes = existingValues.values.reduce(0) {
            $0 + (($1 as? String)?.utf8.count ?? ($1 as? Data)?.count ?? 0)
        }
        let replacedBytes = defaults.string(forKey: key)?.utf8.count ?? 0
        guard existingBytes - replacedBytes + json.utf8.count <= maximumBytes else { return false }
        defaults.removeObject(forKey: dataPrefix + key)
        defaults.set(json, forKey: key)
        return true
    }

    func dataResponse(for key: String, shared: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared, Self.valid(key: key) else { return #"{"allowed":false}"# }
        guard let data = defaults.data(forKey: dataPrefix + key) else {
            return #"{"allowed":true,"found":false}"#
        }
        guard let encoded = try? JSONEncoder().encode(data.base64EncodedString()),
              let literal = String(data: encoded, encoding: .utf8) else {
            return #"{"allowed":true,"found":false}"#
        }
        return #"{"allowed":true,"found":true,"base64":\#(literal)}"#
    }

    func setData(base64: String, for key: String, shared: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared, Self.valid(key: key),
              let data = Data(base64Encoded: base64), data.count <= maximumBytes else { return false }
        let existingValues = defaults.persistentDomain(forName: suiteName) ?? [:]
        let existingBytes = existingValues.reduce(0) { result, item in
            result + ((item.value as? String)?.utf8.count ?? (item.value as? Data)?.count ?? 0)
        }
        let dataKey = dataPrefix + key
        let replacedBytes = defaults.data(forKey: dataKey)?.count
            ?? defaults.string(forKey: key)?.utf8.count
            ?? 0
        guard existingBytes - replacedBytes + data.count <= maximumBytes else { return false }
        defaults.removeObject(forKey: key)
        defaults.set(data, forKey: dataKey)
        return true
    }

    func remove(key: String, shared: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared, Self.valid(key: key) else { return false }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: dataPrefix + key)
        return true
    }

    func contains(key: String, shared: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared, Self.valid(key: key) else { return false }
        return defaults.object(forKey: key) != nil || defaults.data(forKey: dataPrefix + key) != nil
    }

    func keysResponse(shared: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        guard allowed, !shared else { return #"{"allowed":false}"# }
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        let keys = Set(domain.keys.map { key in
            key.hasPrefix(dataPrefix) ? String(key.dropFirst(dataPrefix.count)) : key
        }).sorted()
        guard let data = try? JSONEncoder().encode(keys),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"allowed":true,"keys":[]}"#
        }
        return #"{"allowed":true,"keys":\#(json)}"#
    }

    func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard allowed else { return false }
        defaults.removePersistentDomain(forName: suiteName)
        return true
    }

    private static func valid(key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= 1_024 && !key.contains("\0")
    }
}

private enum HanlinScriptingApplicationError: Error, LocalizedError {
    case runtimeInitializationFailed
    case storageInitializationFailed
    case evaluationFailed(String)
    case invalidUITree
    case missingPresentedUI
    case missingWidgetPresentation
    case unknownAppIntent
    case appIntentDidNotComplete
    case invalidAppIntentResult
    case appIntentFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeInitializationFailed: "The Scripting JavaScript runtime could not be created."
        case .storageInitializationFailed: "Package-scoped storage could not be created."
        case let .evaluationFailed(message): "The script failed during launch: \(message)"
        case .invalidUITree: "The script produced an invalid or unsupported UI tree."
        case .missingPresentedUI: "The app entrypoint did not call Navigation.present."
        case .missingWidgetPresentation: "The widget entrypoint did not call Widget.present."
        case .unknownAppIntent: "The requested App Intent is not registered."
        case .appIntentDidNotComplete: "The App Intent did not complete."
        case .invalidAppIntentResult: "The App Intent returned an unsupported value."
        case let .appIntentFailed(message): "The App Intent failed: \(message)"
        }
    }
}

private extension HanlinScriptingApplicationSession {
    static let bootstrap = #"""
    (() => {
      "use strict";
      const state = [];
      const effects = new Map();
      const handlers = new Map();
      const contexts = new Map();
      let navigationDestinationBuilders = [];
      let hookCursor = 0;
      let handlerCursor = 0;
      let presentedElement = null;
      let dismissPresentation = null;
      let rendering = false;
      let renderPending = false;
      let renderScheduled = false;
      let scrollRevision = 0;
      let scrollTarget = null;
      let scrollAnchor = null;
      let nativeRequestCounter = 0;
      const nativeRequests = new Map();
      const assistantStreams = new Map();

      function nativeError(value) {
        const error = new Error(value?.message || "The native operation failed.");
        error.name = value?.name || "Error";
        error.code = value?.code || "native_failure";
        return error;
      }

      function decodeNativeResult(json) {
        const result = JSON.parse(json);
        if (!result.ok) throw nativeError(result.error);
        return result.value;
      }

      function nativeCallSync(operation, payload = {}) {
        return decodeNativeResult(__hanlinNativeFileSync(operation, JSON.stringify(payload)));
      }

      function nativeCallAsync(operation, payload = {}, signal = null) {
        if (signal?.aborted) return Promise.reject(signal.reason ?? abortError());
        const id = `native-${++nativeRequestCounter}`;
        return new Promise((resolve, reject) => {
          const onAbort = () => {
            if (!nativeRequests.delete(id)) return;
            __hanlinCancelNative(id);
            reject(signal.reason ?? abortError());
          };
          if (signal) signal.addEventListener("abort", onAbort);
          nativeRequests.set(id, { resolve, reject, signal, onAbort });
          __hanlinNativeAsync(id, operation, JSON.stringify(payload));
        });
      }

      function resolveNativeRequest(id, json) {
        const request = nativeRequests.get(id);
        if (!request) return;
        nativeRequests.delete(id);
        request.signal?.removeEventListener("abort", request.onAbort);
        try { request.resolve(decodeNativeResult(json)); }
        catch (error) { request.reject(error); }
      }

      class HanlinAssistantStream {
        constructor(id) {
          this.id = id;
          this.queue = [];
          this.waiter = null;
          this.terminalError = null;
          this.finished = false;
          this.cancelled = false;
        }
        [Symbol.asyncIterator]() { return this; }
        next() {
          if (this.queue.length > 0) return Promise.resolve({ value: this.queue.shift(), done: false });
          if (this.terminalError) return Promise.reject(this.terminalError);
          if (this.finished) return Promise.resolve({ value: undefined, done: true });
          if (this.waiter) return Promise.reject(new TypeError("Assistant streams must be read sequentially"));
          return new Promise((resolve, reject) => { this.waiter = { resolve, reject }; });
        }
        return() {
          if (!this.finished && !this.cancelled) {
            this.cancelled = true;
            assistantStreams.delete(this.id);
            __hanlinCancelNative(this.id);
          }
          this.finished = true;
          this.waiter?.resolve({ value: undefined, done: true });
          this.waiter = null;
          this.queue.length = 0;
          return Promise.resolve({ value: undefined, done: true });
        }
        push(chunk) {
          if (this.finished || this.cancelled) return;
          if (this.waiter) {
            const waiter = this.waiter;
            this.waiter = null;
            waiter.resolve({ value: chunk, done: false });
          } else {
            if (this.queue.length >= 256) {
              this.fail(new Error("Assistant stream buffer limit exceeded"));
              __hanlinCancelNative(this.id);
              return;
            }
            this.queue.push(chunk);
          }
        }
        finish() {
          if (this.finished || this.cancelled) return;
          this.finished = true;
          assistantStreams.delete(this.id);
          this.waiter?.resolve({ value: undefined, done: true });
          this.waiter = null;
        }
        fail(error) {
          if (this.finished || this.cancelled) return;
          this.finished = true;
          this.terminalError = error;
          assistantStreams.delete(this.id);
          this.waiter?.reject(error);
          this.waiter = null;
          this.queue.length = 0;
        }
      }

      function receiveAssistantChunk(id, json) {
        const stream = assistantStreams.get(id);
        if (!stream) return;
        let result;
        try { result = JSON.parse(json); }
        catch (_) { stream.fail(new Error("The Assistant bridge returned invalid JSON.")); return; }
        if (!result.ok) { stream.fail(nativeError(result.error)); return; }
        if (result.value === null) { stream.finish(); return; }
        stream.push(result.value);
      }

      function normalizeAssistantProvider(provider) {
        if (provider == null) return null;
        if (["openai", "gemini", "anthropic", "deepseek", "openrouter"].includes(provider)) {
          return provider;
        }
        if (typeof provider === "object" && provider !== null
            && Object.keys(provider).length === 1
            && typeof provider.custom === "string" && provider.custom.length > 0) {
          return { custom: provider.custom };
        }
        throw new TypeError("Invalid Assistant provider");
      }

      function validateAssistantContent(content, depth = 0) {
        if (depth > 16) throw new TypeError("Assistant message content is too deeply nested");
        if (typeof content === "string") return;
        if (Array.isArray(content)) {
          if (content.length > 64) throw new TypeError("Assistant message content is too large");
          content.forEach(item => validateAssistantContent(item, depth + 1));
          return;
        }
        if (!content || typeof content !== "object") throw new TypeError("Invalid Assistant message content");
        if (content.type === "text" && typeof content.content === "string") return;
        if (content.type === "image" && typeof content.content === "string"
            && content.content.startsWith("data:image/") && content.content.includes(";base64,")) return;
        if (content.type === "document" && content.content && typeof content.content === "object"
            && typeof content.content.mediaType === "string"
            && typeof content.content.data === "string") return;
        throw new TypeError("Invalid Assistant message content");
      }

      function normalizeAssistantMessages(messages) {
        const values = Array.isArray(messages) ? messages : [messages];
        if (values.length === 0 || values.length > 128) throw new TypeError("Assistant messages are required");
        return values.map(message => {
          if (!message || (message.role !== "user" && message.role !== "assistant")) {
            throw new TypeError("Invalid Assistant message role");
          }
          validateAssistantContent(message.content);
          return { role: message.role, content: message.content };
        });
      }

      function validateAssistantSchema(schema, state = { nodes: 0 }, depth = 0) {
        if (!schema || typeof schema !== "object" || Array.isArray(schema) || depth > 32) {
          throw new TypeError("Invalid Assistant JSON schema");
        }
        if (++state.nodes > 4096) throw new TypeError("Assistant JSON schema is too large");
        if (!["string", "number", "boolean", "object", "array"].includes(schema.type)) {
          throw new TypeError("Invalid Assistant JSON schema type");
        }
        if (typeof schema.description !== "string") throw new TypeError("Assistant schema descriptions are required");
        if (schema.required !== undefined && typeof schema.required !== "boolean") {
          throw new TypeError("Invalid Assistant schema required flag");
        }
        if (schema.type === "object") {
          if (!schema.properties || typeof schema.properties !== "object" || Array.isArray(schema.properties)) {
            throw new TypeError("Assistant object schemas require properties");
          }
          for (const value of Object.values(schema.properties)) validateAssistantSchema(value, state, depth + 1);
        }
        if (schema.type === "array") validateAssistantSchema(schema.items, state, depth + 1);
        return schema;
      }

      function startAssistantStream(payload) {
        const id = `assistant-${++nativeRequestCounter}`;
        const stream = new HanlinAssistantStream(id);
        assistantStreams.set(id, stream);
        __hanlinNativeAssistantStart(id, JSON.stringify(payload));
        return stream;
      }

      class HanlinDOMException extends Error {
        constructor(message = "", name = "Error") { super(message); this.name = name; }
        get code() { return this.name === "AbortError" ? 20 : this.name === "TimeoutError" ? 23 : 0; }
      }

      function abortError(message = "The operation was aborted.") { return new HanlinDOMException(message, "AbortError"); }
      function timeoutError(message = "The operation timed out.") { return new HanlinDOMException(message, "TimeoutError"); }

      class HanlinAbortEvent {
        constructor(signal) { this.type = "abort"; this.target = signal; }
      }

      class HanlinAbortSignal {
        constructor() { this.aborted = false; this.reason = undefined; this.onabort = null; this.listeners = new Set(); }
        throwIfAborted() { if (this.aborted) throw this.reason ?? abortError(); }
        addEventListener(type, listener) { if (type === "abort" && typeof listener === "function") this.listeners.add(listener); }
        removeEventListener(type, listener) { if (type === "abort") this.listeners.delete(listener); }
        _abort(reason) {
          if (this.aborted) return;
          this.aborted = true;
          this.reason = reason === undefined ? abortError() : reason;
          const event = new HanlinAbortEvent(this);
          try { this.onabort?.(event); } catch (_) {}
          for (const listener of [...this.listeners]) { try { listener(event); } catch (_) {} }
          this.listeners.clear();
        }
        static abort(reason) { const signal = new HanlinAbortSignal(); signal._abort(reason); return signal; }
        static timeout(delay) {
          const milliseconds = Number(delay);
          if (!Number.isFinite(milliseconds) || milliseconds < 0) throw new TypeError("Delay must be a non-negative finite number");
          const controller = new HanlinAbortController();
          nativeCallAsync("runtime.delay", { milliseconds }).then(
            () => controller.abort(timeoutError()),
            error => { if (error?.name !== "AbortError") controller.abort(error); }
          );
          return controller.signal;
        }
        static any(signals) {
          const controller = new HanlinAbortController();
          for (const signal of signals) {
            if (signal.aborted) { controller.abort(signal.reason); break; }
            signal.addEventListener("abort", () => controller.abort(signal.reason));
          }
          return controller.signal;
        }
      }

      class HanlinAbortController {
        constructor() { this.signal = new HanlinAbortSignal(); }
        abort(reason) { this.signal._abort(reason); }
      }

      function utf8Bytes(value) {
        const encoded = unescape(encodeURIComponent(String(value)));
        return Uint8Array.from(encoded, character => character.charCodeAt(0));
      }

      function utf8String(bytes) {
        let binary = "";
        for (let index = 0; index < bytes.length; index += 0x8000) {
          binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
        }
        try { return decodeURIComponent(escape(binary)); }
        catch (_) { return binary.replace(/[^\x00-\x7f]/g, "\ufffd"); }
      }

      const base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      function bytesToBase64(bytes) {
        let output = "";
        for (let index = 0; index < bytes.length; index += 3) {
          const first = bytes[index];
          const second = index + 1 < bytes.length ? bytes[index + 1] : 0;
          const third = index + 2 < bytes.length ? bytes[index + 2] : 0;
          const value = (first << 16) | (second << 8) | third;
          output += base64Alphabet[(value >>> 18) & 63];
          output += base64Alphabet[(value >>> 12) & 63];
          output += index + 1 < bytes.length ? base64Alphabet[(value >>> 6) & 63] : "=";
          output += index + 2 < bytes.length ? base64Alphabet[value & 63] : "=";
        }
        return output;
      }

      function base64ToBytes(value) {
        const input = String(value).replace(/\s+/g, "");
        if (input.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(input)) return null;
        const output = [];
        for (let index = 0; index < input.length; index += 4) {
          const a = base64Alphabet.indexOf(input[index]);
          const b = base64Alphabet.indexOf(input[index + 1]);
          const c = input[index + 2] === "=" ? 0 : base64Alphabet.indexOf(input[index + 2]);
          const d = input[index + 3] === "=" ? 0 : base64Alphabet.indexOf(input[index + 3]);
          if (a < 0 || b < 0 || c < 0 || d < 0) return null;
          const combined = (a << 18) | (b << 12) | (c << 6) | d;
          output.push((combined >>> 16) & 255);
          if (input[index + 2] !== "=") output.push((combined >>> 8) & 255);
          if (input[index + 3] !== "=") output.push(combined & 255);
        }
        return Uint8Array.from(output);
      }

      class HanlinData {
        constructor(bytes) { this.bytes = Uint8Array.from(bytes ?? []); }
        get size() { return this.bytes.length; }
        resetBytes(startIndex, endIndex) { this.bytes.fill(0, startIndex, endIndex); }
        advanced(amount) { return new HanlinData(this.bytes.slice(amount)); }
        replaceSubrange(startIndex, endIndex, data) {
          const output = new Uint8Array(this.size - (endIndex - startIndex) + data.size);
          output.set(this.bytes.slice(0, startIndex));
          output.set(data.bytes, startIndex);
          output.set(this.bytes.slice(endIndex), startIndex + data.size);
          this.bytes = output;
        }
        slice(start = 0, end = this.size) { return new HanlinData(this.bytes.slice(start, end)); }
        append(other) {
          const output = new Uint8Array(this.size + other.size);
          output.set(this.bytes); output.set(other.bytes, this.size); this.bytes = output;
        }
        getBytes() { return this.toUint8Array(); }
        toUint8Array() { return new Uint8Array(this.bytes); }
        toArrayBuffer() { return this.toUint8Array().buffer; }
        toBase64String() { return bytesToBase64(this.bytes); }
        toHexString() { return [...this.bytes].map(value => value.toString(16).padStart(2, "0")).join(""); }
        toRawString(encoding = "utf8") {
          if (!["utf8", "utf-8", "ascii"].includes(encoding)) throw new Error("HANLIN_DATA:unsupported_encoding");
          return encoding === "ascii" ? String.fromCharCode(...this.bytes) : utf8String(this.bytes);
        }
        toDecodedString(encoding = "utf8") { return this.toRawString(encoding); }
        toIntArray() { return [...this.bytes]; }
        static fromIntArray(value) { return new HanlinData(Uint8Array.from(value)); }
        static fromString(value, encoding) { return this.fromRawString(value, encoding); }
        static fromRawString(value, encoding = "utf8") {
          if (!["utf8", "utf-8", "ascii"].includes(encoding)) throw new Error("HANLIN_DATA:unsupported_encoding");
          return new HanlinData(encoding === "ascii" ? Uint8Array.from([...String(value)], item => item.charCodeAt(0) & 255) : utf8Bytes(value));
        }
        static fromFile(path) {
          try { return new HanlinData(base64ToBytes(nativeCallSync("file.readData", { path }))); }
          catch (_) { return null; }
        }
        static fromArrayBuffer(value) { return value?.byteLength ? new HanlinData(new Uint8Array(value)) : null; }
        static fromUint8Array(value) { return value?.byteLength ? new HanlinData(value) : null; }
        static fromBase64String(value) { const bytes = base64ToBytes(value); return bytes ? new HanlinData(bytes) : null; }
        static fromHexString(value) {
          const text = String(value); if (text.length % 2 || /[^0-9a-f]/i.test(text)) return null;
          return new HanlinData(Uint8Array.from(text.match(/../g) ?? [], item => parseInt(item, 16)));
        }
        static combine(values) {
          const output = new HanlinData(); for (const value of values) output.append(value); return output;
        }
        static fromJPEG(image, compressionQuality = 1) {
          if (!(image instanceof HanlinUIImage)) return null;
          if (typeof compressionQuality !== "number" || !Number.isFinite(compressionQuality)
              || compressionQuality < 0 || compressionQuality > 1) return null;
          return image.toJPEGData(compressionQuality);
        }
        static fromPNG(image) {
          return image instanceof HanlinUIImage ? image.toPNGData() : null;
        }
      }

      class HanlinUIImage {
        constructor(encodedData) {
          if (!(encodedData instanceof HanlinData) || encodedData.size === 0) {
            throw new TypeError("UIImage requires non-empty encoded image data");
          }
          this._encodedData = encodedData.slice();
          this.size = Object.freeze({ width: 0, height: 0 });
          this.scale = 1;
          this.imageOrientation = "up";
        }
        toJPEGData(compressionQuality = 1) {
          if (typeof compressionQuality !== "number" || !Number.isFinite(compressionQuality)
              || compressionQuality < 0 || compressionQuality > 1) return null;
          try {
            const base64 = decodeNativeResult(__hanlinNativeImageJPEG(
              this._encodedData.toBase64String(), compressionQuality
            ));
            return HanlinData.fromBase64String(base64);
          } catch (_) { return null; }
        }
        toPNGData() { return null; }
        toBase64String() { return this._encodedData.toBase64String(); }
        static fromData(data) {
          try { return data instanceof HanlinData && data.size > 0 ? new HanlinUIImage(data) : null; }
          catch (_) { return null; }
        }
        static fromFile(path) {
          try { return this.fromData(HanlinData.fromFile(path)); }
          catch (_) { return null; }
        }
        static fromBase64String(value) { return this.fromData(HanlinData.fromBase64String(value)); }
      }

      function normalizePath(path) {
        if (typeof path !== "string") throw new TypeError("Path must be a string");
        if (!path) return ".";
        const absolute = path.startsWith("/");
        const trailing = path.endsWith("/");
        const parts = [];
        for (const part of path.split("/")) {
          if (!part || part === ".") continue;
          if (part === "..") {
            if (parts.length && parts[parts.length - 1] !== "..") parts.pop();
            else if (!absolute) parts.push("..");
          } else parts.push(part);
        }
        let result = `${absolute ? "/" : ""}${parts.join("/")}`;
        if (!result) result = absolute ? "/" : ".";
        if (trailing && result !== "/" && result !== ".") result += "/";
        return result;
      }

      const Path = Object.freeze({
        sep: "/", delimiter: ":", normalize: normalizePath,
        isAbsolute(path) { if (typeof path !== "string") throw new TypeError("Path must be a string"); return path.startsWith("/"); },
        join(...parts) {
          if (parts.some(part => typeof part !== "string")) throw new TypeError("Path segments must be strings");
          return normalizePath(parts.filter(Boolean).join("/"));
        },
        dirname(path) {
          const normalized = normalizePath(path).replace(/\/+$/, "");
          if (normalized === "/") return "/";
          const index = normalized.lastIndexOf("/");
          if (index < 0) return ".";
          return index === 0 ? "/" : normalized.slice(0, index);
        },
        basename(path, extension = "") {
          const normalized = normalizePath(path).replace(/\/+$/, "");
          let base = normalized.slice(normalized.lastIndexOf("/") + 1);
          if (extension && base.endsWith(extension)) base = base.slice(0, -extension.length);
          return base;
        },
        extname(path) {
          const base = this.basename(path); const index = base.lastIndexOf(".");
          return index <= 0 ? "" : base.slice(index);
        },
        parse(path) {
          const root = this.isAbsolute(path) ? "/" : ""; const dir = this.dirname(path);
          const base = this.basename(path); const ext = this.extname(path);
          return { root, dir, base, ext, name: ext ? base.slice(0, -ext.length) : base };
        }
      });

      const fileInfo = decodeNativeResult(__hanlinNativeFileInfo());
      function filePayload(path, extra = {}) { return { path: normalizePath(path), ...extra }; }
      const FileManager = {
        ...fileInfo,
        mimeType(path) { return nativeCallSync("file.mimeType", filePayload(path)); },
        createDirectory(path, recursive = false) { return nativeCallAsync("file.createDirectory", filePayload(path, { recursive })); },
        createDirectorySync(path, recursive = false) { nativeCallSync("file.createDirectory", filePayload(path, { recursive })); },
        copyFile(path, newPath) { return nativeCallAsync("file.copy", filePayload(path, { newPath: normalizePath(newPath) })); },
        copyFileSync(path, newPath) { nativeCallSync("file.copy", filePayload(path, { newPath: normalizePath(newPath) })); },
        readDirectory(path, recursive = false) { return nativeCallAsync("file.readDirectory", filePayload(path, { recursive })); },
        readDirectorySync(path, recursive = false) { return nativeCallSync("file.readDirectory", filePayload(path, { recursive })); },
        exists(path) { return nativeCallAsync("file.exists", filePayload(path)); },
        existsSync(path) { return nativeCallSync("file.exists", filePayload(path)); },
        isFile(path) { return nativeCallAsync("file.isFile", filePayload(path)); },
        isFileSync(path) { return nativeCallSync("file.isFile", filePayload(path)); },
        isDirectory(path) { return nativeCallAsync("file.isDirectory", filePayload(path)); },
        isDirectorySync(path) { return nativeCallSync("file.isDirectory", filePayload(path)); },
        isLink(path) { return nativeCallAsync("file.isLink", filePayload(path)); },
        isLinkSync(path) { return nativeCallSync("file.isLink", filePayload(path)); },
        readAsData(path) { return nativeCallAsync("file.readData", filePayload(path)).then(value => HanlinData.fromBase64String(value)); },
        readAsDataSync(path) { return HanlinData.fromBase64String(nativeCallSync("file.readData", filePayload(path))); },
        readAsBytes(path) { return this.readAsData(path).then(value => value.toUint8Array()); },
        readAsBytesSync(path) { return this.readAsDataSync(path).toUint8Array(); },
        readAsString(path, encoding = "utf8") { return this.readAsData(path).then(value => value.toRawString(encoding)); },
        readAsStringSync(path, encoding = "utf8") { return this.readAsDataSync(path).toRawString(encoding); },
        writeAsData(path, data) { return nativeCallAsync("file.writeData", filePayload(path, { base64: data.toBase64String() })); },
        writeAsDataSync(path, data) { nativeCallSync("file.writeData", filePayload(path, { base64: data.toBase64String() })); },
        writeAsBytes(path, data) { return this.writeAsData(path, new HanlinData(data)); },
        writeAsBytesSync(path, data) { this.writeAsDataSync(path, new HanlinData(data)); },
        writeAsString(path, value, encoding = "utf8") { return this.writeAsData(path, HanlinData.fromRawString(value, encoding)); },
        writeAsStringSync(path, value, encoding = "utf8") { this.writeAsDataSync(path, HanlinData.fromRawString(value, encoding)); },
        appendData(path, data) { return nativeCallAsync("file.appendData", filePayload(path, { base64: data.toBase64String() })); },
        appendDataSync(path, data) { nativeCallSync("file.appendData", filePayload(path, { base64: data.toBase64String() })); },
        appendText(path, value, encoding = "utf8") { return this.appendData(path, HanlinData.fromRawString(value, encoding)); },
        appendTextSync(path, value, encoding = "utf8") { this.appendDataSync(path, HanlinData.fromRawString(value, encoding)); },
        stat(path) { return nativeCallAsync("file.stat", filePayload(path)); },
        statSync(path) { return nativeCallSync("file.stat", filePayload(path)); },
        rename(path, newPath) { return nativeCallAsync("file.rename", filePayload(path, { newPath: normalizePath(newPath) })); },
        renameSync(path, newPath) { nativeCallSync("file.rename", filePayload(path, { newPath: normalizePath(newPath) })); },
        remove(path) { return nativeCallAsync("file.remove", filePayload(path)); },
        removeSync(path) { nativeCallSync("file.remove", filePayload(path)); },
        isBinaryFile(path) { return this.readAsData(path).then(value => value.toIntArray().includes(0)); },
        isBinaryFileSync(path) { return this.readAsDataSync(path).toIntArray().includes(0); },
        isFileStoredIniCloud() { return false; }, isiCloudFileDownloaded() { return false; },
        downloadFileFromiCloud() { return Promise.resolve(false); },
        addFileBookmark() { return null; }, removeFileBookmark() { return false; },
        bookmarkExists() { return false; }, getAllFileBookmarks() { return []; }, bookmarkedPath() { return null; }
      };
      Object.defineProperties(FileManager, {
        iCloudDocumentsDirectory: { get() { throw new Error("HANLIN_FILE:iCloud_unavailable"); } },
        webDAVDocumentsDirectory: { get() { throw new Error("HANLIN_FILE:webdav_unavailable"); } }
      });
      Object.freeze(FileManager);

      class HanlinHeaders {
        constructor(initial = undefined) {
          this.store = new Map();
          if (initial instanceof HanlinHeaders) {
            for (const [name, value] of initial.rawEntries()) this.append(name, value);
          } else if (Array.isArray(initial)) {
            for (const pair of initial) {
              if (!Array.isArray(pair) || pair.length !== 2) throw new TypeError("Invalid header pair");
              this.append(pair[0], pair[1]);
            }
          } else if (initial && typeof initial === "object") {
            for (const [name, value] of Object.entries(initial)) this.append(name, value);
          }
        }
        normalizeName(name) {
          const value = String(name).trim().toLowerCase();
          if (!value || /[^!#$%&'*+.^_`|~0-9a-z-]/.test(value)) throw new TypeError("Invalid header name");
          return value;
        }
        normalizeValue(value) { return String(value).trim(); }
        append(name, value) {
          const key = this.normalizeName(name); const normalized = this.normalizeValue(value);
          const entry = this.store.get(key) ?? { name: String(name), values: [] };
          entry.values.push(normalized); this.store.set(key, entry);
        }
        set(name, value) { const key = this.normalizeName(name); this.store.set(key, { name: String(name), values: [this.normalizeValue(value)] }); }
        get(name) { const entry = this.store.get(this.normalizeName(name)); return entry ? entry.values.join(", ") : null; }
        getSetCookie() { return this.store.get("set-cookie")?.values.slice() ?? []; }
        has(name) { return this.store.has(this.normalizeName(name)); }
        delete(name) { this.store.delete(this.normalizeName(name)); }
        *rawEntries() { for (const entry of this.store.values()) for (const value of entry.values) yield [entry.name, value]; }
        entries() { return [...this.store].map(([key, entry]) => [key, entry.values.join(", ")]); }
        keys() { return this.entries().map(value => value[0]); }
        values() { return this.entries().map(value => value[1]); }
        forEach(callback, thisArg) { for (const [name, value] of this.entries()) callback.call(thisArg, value, name, this); }
        [Symbol.iterator]() { return this.entries()[Symbol.iterator](); }
        toObject() { const output = {}; for (const [name, value] of this.entries()) output[name] = value; return output; }
        toJson() { return this.toObject(); }
      }

      class HanlinBlob {
        constructor(parts = [], options = {}) {
          this.type = String(options.type ?? "").toLowerCase();
          this.dataValue = new HanlinData();
          for (const part of parts) this.dataValue.append(bodyData(part));
        }
        get size() { return this.dataValue.size; }
        arrayBuffer() { return Promise.resolve(this.dataValue.toArrayBuffer()); }
        bytes() { return Promise.resolve(this.dataValue.toUint8Array()); }
        text() { return Promise.resolve(this.dataValue.toDecodedString()); }
        data() { return Promise.resolve(this.dataValue.slice()); }
        slice(start = 0, end = this.size, type = "") { return new HanlinBlob([this.dataValue.slice(start, end)], { type }); }
      }

      class HanlinFormData {
        constructor() { this.items = []; }
        append(name, value, mimeType, filename) { this.items.push({ name: String(name), value, mimeType, filename }); }
        set(name, value, mimeType, filename) { this.delete(name); this.append(name, value, mimeType, filename); }
        get(name) { return this.items.find(item => item.name === String(name))?.value ?? null; }
        getAll(name) { return this.items.filter(item => item.name === String(name)).map(item => item.value); }
        has(name) { return this.items.some(item => item.name === String(name)); }
        delete(name) { this.items = this.items.filter(item => item.name !== String(name)); }
        forEach(callback, thisArg) { for (const item of this.items) callback.call(thisArg, item.value, item.name, this); }
        entries() { return this.items.map(item => [item.name, item.value]); }
        keys() { return this.items.map(item => item.name); }
        values() { return this.items.map(item => item.value); }
        [Symbol.iterator]() { return this.entries()[Symbol.iterator](); }
        toJson() {
          const output = {};
          for (const item of this.items) (output[item.name] ??= []).push(item.value);
          return output;
        }
        _encode() {
          const boundary = `hanlin-${Math.random().toString(16).slice(2)}-${Date.now()}`;
          const output = new HanlinData();
          for (const item of this.items) {
            output.append(HanlinData.fromRawString(`--${boundary}\r\nContent-Disposition: form-data; name="${item.name.replace(/["\r\n]/g, "")}"`));
            if (item.filename) output.append(HanlinData.fromRawString(`; filename="${String(item.filename).replace(/["\r\n]/g, "")}"`));
            if (item.mimeType) output.append(HanlinData.fromRawString(`\r\nContent-Type: ${item.mimeType}`));
            output.append(HanlinData.fromRawString("\r\n\r\n"));
            output.append(bodyData(item.value));
            output.append(HanlinData.fromRawString("\r\n"));
          }
          output.append(HanlinData.fromRawString(`--${boundary}--\r\n`));
          return { data: output, contentType: `multipart/form-data; boundary=${boundary}` };
        }
      }

      function bodyData(value) {
        if (value == null) return new HanlinData();
        if (value instanceof HanlinData) return value.slice();
        if (value instanceof HanlinBlob) return value.dataValue.slice();
        if (value instanceof Uint8Array) return new HanlinData(value);
        if (value instanceof ArrayBuffer) return new HanlinData(new Uint8Array(value));
        return HanlinData.fromRawString(String(value));
      }

      class HanlinRequest {
        constructor(input, init = {}) {
          const source = input instanceof HanlinRequest ? input : null;
          this.url = String(source?.url ?? input);
          this.method = String(init.method ?? source?.method ?? "GET").toUpperCase();
          this.headers = new HanlinHeaders(init.headers ?? source?.headers);
          this.signal = init.signal ?? source?.signal ?? null;
          this.timeout = init.timeout ?? source?.timeout;
          this.allowInsecureRequest = init.allowInsecureRequest ?? source?.allowInsecureRequest ?? false;
          this.debugLabel = init.debugLabel ?? source?.debugLabel;
          this.bodyUsed = false;
          const body = Object.hasOwn(init, "body") ? init.body : source?.bodyValue;
          if ((this.method === "GET" || this.method === "HEAD") && body != null) throw new TypeError("GET and HEAD requests cannot have a body");
          if (body instanceof HanlinFormData) {
            const encoded = body._encode(); this.bodyValue = encoded.data;
            if (!this.headers.has("content-type")) this.headers.set("content-type", encoded.contentType);
          } else this.bodyValue = body == null ? null : bodyData(body);
        }
        clone() { if (this.bodyUsed) throw new TypeError("Body has already been used"); return new HanlinRequest(this); }
        _consume() { if (this.bodyUsed) return Promise.reject(new TypeError("Body has already been used")); this.bodyUsed = true; return Promise.resolve(this.bodyValue ?? new HanlinData()); }
        arrayBuffer() { return this._consume().then(value => value.toArrayBuffer()); }
        data() { return this._consume(); }
        text() { return this._consume().then(value => value.toDecodedString()); }
        json() { return this.text().then(JSON.parse); }
      }

      class HanlinResponse {
        constructor(body = null, init = {}) {
          this.status = Number(init.status ?? 200); this.statusText = String(init.statusText ?? "");
          this.headers = new HanlinHeaders(init.headers); this.url = String(init.url ?? "");
          this.redirected = Boolean(init.redirected); this.type = "basic"; this.bodyUsed = false;
          this.bodyValue = body == null ? new HanlinData() : bodyData(body);
        }
        get ok() { return this.status >= 200 && this.status <= 299; }
        get cookies() { return this.headers.getSetCookie(); }
        clone() { if (this.bodyUsed) throw new TypeError("Body has already been used"); return new HanlinResponse(this.bodyValue.slice(), { status: this.status, statusText: this.statusText, headers: this.headers, url: this.url, redirected: this.redirected }); }
        _consume() { if (this.bodyUsed) return Promise.reject(new TypeError("Body has already been used")); this.bodyUsed = true; return Promise.resolve(this.bodyValue); }
        arrayBuffer() { return this._consume().then(value => value.toArrayBuffer()); }
        blob() { return this._consume().then(value => new HanlinBlob([value], { type: this.headers.get("content-type") ?? "" })); }
        bytes() { return this._consume().then(value => value.toUint8Array()); }
        data() { return this._consume().then(value => value.slice()); }
        text() { return this._consume().then(value => value.toDecodedString()); }
        json() { return this.text().then(JSON.parse); }
        static json(value, init = {}) { const headers = new HanlinHeaders(init.headers); if (!headers.has("content-type")) headers.set("content-type", "application/json"); return new HanlinResponse(JSON.stringify(value), { ...init, headers }); }
        static redirect(url, status = 302) { return new HanlinResponse(null, { status, headers: { location: String(url) } }); }
      }

      function hanlinFetch(input, init = undefined) {
        let request;
        try { request = new HanlinRequest(input, init); }
        catch (error) { return Promise.reject(error); }
        return nativeCallAsync("network.fetch", {
          url: request.url,
          method: request.method,
          headers: request.headers.toObject(),
          bodyBase64: request.bodyValue?.toBase64String() ?? null,
          timeout: request.timeout ?? null,
          allowInsecureRequest: request.allowInsecureRequest
        }, request.signal).then(result => new HanlinResponse(
          HanlinData.fromBase64String(result.bodyBase64) ?? new HanlinData(),
          { status: result.status, headers: result.headers, url: result.url }
        ));
      }

      const locationAccuracies = new Set([
        "best", "tenMeters", "hundredMeters", "kilometer", "threeKilometers",
        "bestForNavigation", "reduced"
      ]);
      let locationAccuracy = "best";
      const Location = {
        get accuracy() { return locationAccuracy; },
        requestCurrent(options = {}) {
          if (options == null || typeof options !== "object" || Array.isArray(options)) {
            return Promise.reject(new TypeError("Location options must be an object"));
          }
          if (options.forceRequest !== undefined && typeof options.forceRequest !== "boolean") {
            return Promise.reject(new TypeError("Location forceRequest must be a Boolean"));
          }
          return nativeCallAsync("location.requestCurrent", {
            forceRequest: options.forceRequest ?? false
          });
        },
        geocodeAddress(options) {
          if (!options || typeof options.address !== "string") {
            return Promise.reject(new TypeError("Location geocoding requires an address"));
          }
          return nativeCallAsync("location.geocodeAddress", {
            address: options.address,
            locale: options.locale ?? null
          });
        },
        reverseGeocode(options) {
          if (!options || typeof options !== "object") {
            return Promise.reject(new TypeError("Location reverse geocoding requires coordinates"));
          }
          return nativeCallAsync("location.reverseGeocode", {
            latitude: options.latitude,
            longitude: options.longitude,
            locale: options.locale ?? null
          });
        },
        setAccuracy(accuracy) {
          if (!locationAccuracies.has(accuracy)) {
            return Promise.reject(new TypeError("Invalid Location accuracy"));
          }
          return nativeCallAsync("location.setAccuracy", { accuracy }).then(value => {
            locationAccuracy = accuracy;
            return value;
          });
        }
      };
      Object.freeze(Location);

      const dateComponentKeys = Object.freeze([
        "calendar", "timeZone", "era", "year", "yearForWeekOfYear", "quarter", "month",
        "weekOfMonth", "weekOfYear", "weekday", "weekdayOrdinal", "day", "hour", "minute",
        "second", "nanosecond"
      ]);
      class DateComponents {
        constructor(options = {}) {
          if (options == null || typeof options !== "object" || Array.isArray(options)) {
            throw new TypeError("DateComponents options must be an object");
          }
          for (const key of dateComponentKeys) {
            if (Object.hasOwn(options, key)) this[key] = options[key];
          }
        }
        get date() {
          if (this.year == null || this.month == null || this.day == null) return null;
          const value = new Date(
            Number(this.year), Number(this.month) - 1, Number(this.day),
            Number(this.hour ?? 0), Number(this.minute ?? 0), Number(this.second ?? 0),
            Math.floor(Number(this.nanosecond ?? 0) / 1000000)
          );
          return Number.isNaN(value.getTime()) ? null : value;
        }
        get isValidDate() { return this.date != null; }
        toJSON() {
          const value = {};
          for (const key of dateComponentKeys) if (this[key] != null) value[key] = this[key];
          return value;
        }
        static fromDate(date) {
          const value = new Date(date);
          if (Number.isNaN(value.getTime())) throw new TypeError("A valid date is required");
          return new DateComponents({
            year: value.getFullYear(), month: value.getMonth() + 1, day: value.getDate(),
            weekday: value.getDay() + 1, hour: value.getHours(), minute: value.getMinutes(),
            second: value.getSeconds(), nanosecond: value.getMilliseconds() * 1000000
          });
        }
        static forHourly(date) { const value = this.fromDate(date); return new DateComponents({ minute: value.minute }); }
        static forDaily(date) { const value = this.fromDate(date); return new DateComponents({ hour: value.hour, minute: value.minute }); }
        static forWeekly(date) { const value = this.fromDate(date); return new DateComponents({ weekday: value.weekday, hour: value.hour, minute: value.minute }); }
        static forMonthly(date) { const value = this.fromDate(date); return new DateComponents({ day: value.day, hour: value.hour, minute: value.minute }); }
      }

      class Reminder {
        constructor() {
          this.identifier = null;
          this.calendar = null;
          this.title = "";
          this.notes = null;
          this.isCompleted = false;
          this.priority = 0;
          this.completionDate = null;
          this.dueDateComponents = null;
          this.recurrenceRules = [];
          this.alarms = [];
        }
        save() {
          if (typeof this.title !== "string" || this.title.length === 0) {
            return Promise.reject(new TypeError("Reminder title is required"));
          }
          if (this.dueDateComponents != null && !(this.dueDateComponents instanceof DateComponents)) {
            return Promise.reject(new TypeError("Reminder dueDateComponents must be DateComponents"));
          }
          if (this.isCompleted || this.completionDate != null || this.recurrenceRules.length || this.alarms.length) {
            return Promise.reject(new TypeError("The requested Reminder feature is not supported yet"));
          }
          return nativeCallAsync("reminder.save", {
            title: this.title,
            notes: this.notes,
            priority: this.priority,
            dueDateComponents: this.dueDateComponents
          }).then(identifier => { this.identifier = identifier; });
        }
        remove() { return Promise.reject(new Error("Reminder.remove is not supported yet")); }
        static getAll() { return Promise.reject(new Error("Reminder.getAll is not supported yet")); }
        static getCalendars() { return Promise.reject(new Error("Reminder.getCalendars is not supported yet")); }
      }

      class CalendarNotificationTrigger {
        constructor(options) {
          if (!options || !(options.dateMatching instanceof DateComponents) || typeof options.repeats !== "boolean") {
            throw new TypeError("A CalendarNotificationTrigger requires DateComponents and repeats");
          }
          this.dateComponents = options.dateMatching;
          this.repeats = options.repeats;
          Object.freeze(this);
        }
        nextTriggerDate() { return this.dateComponents.date; }
        toJSON() { return { type: "calendar", dateMatching: this.dateComponents, repeats: this.repeats }; }
      }

      class TimeIntervalNotificationTrigger {
        constructor(options) {
          const interval = Number(options?.timeInterval);
          if (!Number.isFinite(interval) || interval <= 0 || typeof options?.repeats !== "boolean") {
            throw new TypeError("A TimeIntervalNotificationTrigger requires a positive interval and repeats");
          }
          this.timeInterval = interval;
          this.repeats = options.repeats;
          Object.freeze(this);
        }
        nextTriggerDate() { return new Date(Date.now() + this.timeInterval * 1000); }
        toJSON() { return { type: "timeInterval", timeInterval: this.timeInterval, repeats: this.repeats }; }
      }

      class HealthUnit {
        constructor(unitString) { this.unitString = String(unitString); Object.freeze(this); }
        multiplied(unit) { return new HealthUnit(`${this.unitString}*${unit?.unitString ?? unit}`); }
        divided(unit) { return new HealthUnit(`${this.unitString}/${unit?.unitString ?? unit}`); }
        static count() { return new HealthUnit("count"); }
        static minute() { return new HealthUnit("min"); }
        static hour() { return new HealthUnit("hr"); }
        static second() { return new HealthUnit("s"); }
        static meter() { return new HealthUnit("m"); }
        static kilocalorie() { return new HealthUnit("kcal"); }
        static countPerMinute() { return new HealthUnit("count/min"); }
      }

      function healthUnitMatches(actual, requested) {
        if (!(requested instanceof HealthUnit)) throw new TypeError("A HealthUnit is required");
        const normalize = value => String(value).replace(/\s+/g, "").replace("1/min", "count/min");
        return normalize(actual) === normalize(requested.unitString);
      }
      class HealthStatistics {
        constructor(value) {
          this.quantityType = value.quantityType;
          this.sources = null;
          this.startDate = new Date(value.startDate);
          this.endDate = new Date(value.endDate);
          this._unit = value.unit;
          this._sum = value.sum;
          this._average = value.average;
          Object.freeze(this);
        }
        sumQuantity(unit, source = undefined) {
          return source === undefined && healthUnitMatches(this._unit, unit) ? this._sum ?? null : null;
        }
        averageQuantity(unit, source = undefined) {
          return source === undefined && healthUnitMatches(this._unit, unit) ? this._average ?? null : null;
        }
        duration() { return null; }
        minimumQuantity() { return null; }
        maximumQuantity() { return null; }
        mostRecentQuantity() { return null; }
        mostRecentQuantityDateInterval() { return null; }
      }
      class HealthActivitySummary {
        constructor(value) {
          this.dateComponents = new DateComponents(value.dateComponents);
          this.activityMoveMode = value.activityMoveMode;
          this._values = value;
          Object.freeze(this);
        }
        _quantity(key, unit, expectedUnit) {
          if (!healthUnitMatches(expectedUnit, unit)) throw new TypeError("The HealthUnit is incompatible");
          return this._values[key];
        }
        activeEnergyBurned(unit) { return this._quantity("activeEnergyBurned", unit, "kcal"); }
        activeEnergyBurnedGoal(unit) { return this._quantity("activeEnergyBurnedGoal", unit, "kcal"); }
        appleMoveTime(unit) { return this._quantity("appleMoveTime", unit, "min"); }
        appleMoveTimeGoal(unit) { return this._quantity("appleMoveTimeGoal", unit, "min"); }
        appleExerciseTime(unit) { return this._quantity("appleExerciseTime", unit, "min"); }
        appleExerciseTimeGoal(unit) { return this._quantity("appleExerciseTimeGoal", unit, "min"); }
        appleStandHours(unit) { return this._quantity("appleStandHours", unit, "count"); }
        appleStandHoursGoal(unit) { return this._quantity("appleStandHoursGoal", unit, "count"); }
      }
      class HealthWorkout {
        constructor(value) {
          this.uuid = value.uuid;
          this.workoutActivityType = value.workoutActivityType;
          this.startDate = new Date(value.startDate);
          this.endDate = new Date(value.endDate);
          this.duration = value.duration;
          this.metadata = null;
          this.device = null;
          this.workoutEvents = null;
          this.allStatistics = Object.freeze(Object.fromEntries(Object.entries(value.allStatistics ?? {}).map(
            ([key, statistics]) => [key, statistics == null ? null : new HealthStatistics(statistics)]
          )));
          Object.freeze(this);
        }
      }
      const healthStatisticsOptions = new Set(["cumulativeSum", "discreteAverage"]);
      const Health = Object.freeze({
        isHealthDataAvailable: globalThis.__hanlinNativeHealthDataAvailable === true,
        queryStatistics(quantityType, options = {}) {
          if (typeof quantityType !== "string" || options == null || typeof options !== "object") {
            return Promise.reject(new TypeError("Health.queryStatistics requires a quantity type and options"));
          }
          const requested = options.statisticsOptions == null
            ? [] : Array.isArray(options.statisticsOptions) ? options.statisticsOptions : [options.statisticsOptions];
          if (!requested.length || requested.some(value => !healthStatisticsOptions.has(value))) {
            return Promise.reject(new TypeError("A Health statistics option is unsupported"));
          }
          const startDate = options.startDate == null ? new Date(0) : new Date(options.startDate);
          const endDate = options.endDate == null ? new Date() : new Date(options.endDate);
          if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
            return Promise.reject(new TypeError("Health statistics dates are invalid"));
          }
          return nativeCallAsync("health.queryStatistics", {
            quantityType, startDate: startDate.getTime(), endDate: endDate.getTime(),
            statisticsOptions: requested
          }).then(value => value == null ? null : new HealthStatistics(value));
        },
        queryActivitySummaries(options) {
          if (!options || !(options.start instanceof DateComponents) || !(options.end instanceof DateComponents)) {
            return Promise.reject(new TypeError("Health.queryActivitySummaries requires start and end DateComponents"));
          }
          return nativeCallAsync("health.queryActivitySummaries", {
            start: options.start, end: options.end
          }).then(values => values.map(value => new HealthActivitySummary(value)));
        },
        queryWorkouts(options = {}) {
          if (options == null || typeof options !== "object" || Array.isArray(options)) {
            return Promise.reject(new TypeError("Health.queryWorkouts options must be an object"));
          }
          if (options.strictStartDate != null || options.strictEndDate != null || options.requestPermissions != null) {
            return Promise.reject(new TypeError("A requested Health workout option is not supported yet"));
          }
          const payload = {
            limit: options.limit,
            sortDescriptors: options.sortDescriptors,
          };
          if (options.startDate != null) {
            const date = new Date(options.startDate);
            if (Number.isNaN(date.getTime())) return Promise.reject(new TypeError("Health workout startDate is invalid"));
            payload.startDate = date.getTime();
          }
          if (options.endDate != null) {
            const date = new Date(options.endDate);
            if (Number.isNaN(date.getTime())) return Promise.reject(new TypeError("Health workout endDate is invalid"));
            payload.endDate = date.getTime();
          }
          return nativeCallAsync("health.queryWorkouts", payload).then(
            values => values.map(value => new HealthWorkout(value))
          );
        }
      });

      const unsupportedNotificationFields = ["sound", "iconImageData", "actions", "customUI", "tapAction"];
      const Notification = Object.freeze({
        current: null,
        schedule(options) {
          if (!options || typeof options !== "object" || typeof options.title !== "string" || !options.title.length) {
            return Promise.reject(new TypeError("Notification.schedule requires a title"));
          }
          if (unsupportedNotificationFields.some(key => options[key] != null && options[key] !== false)) {
            return Promise.reject(new TypeError("A requested Notification feature is not supported yet"));
          }
          return nativeCallAsync("notification.schedule", {
            title: options.title, subtitle: options.subtitle, body: options.body, badge: options.badge,
            silent: options.silent, interruptionLevel: options.interruptionLevel,
            userInfo: options.userInfo, threadIdentifier: options.threadIdentifier,
            trigger: options.trigger ?? null
          }).then(Boolean);
        },
        removeAllPendingsOfCurrentScript() {
          return nativeCallAsync("notification.removeAllPendingsOfCurrentScript").then(() => undefined);
        }
      });

      const hostKinds = Object.freeze({
        Text: "text", Image: "image", Button: "button", TextField: "textField",
        SecureField: "textField", HStack: "hStack", VStack: "vStack", ZStack: "zStack",
        ScrollView: "scrollView", Group: "group", Spacer: "spacer", Divider: "divider",
        ProgressView: "progress", NavigationStack: "navigationStack",
        NavigationSplitView: "navigationSplitView", ScrollViewReader: "scrollViewReader",
        NavigationLink: "navigationLink", NavigationDestination: "navigationDestination",
        TabView: "tabView", Tab: "tab",
        List: "scrollView", Form: "form", Section: "group", GroupBox: "groupBox",
        LazyVStack: "vStack", LazyVGrid: "lazyVGrid", Grid: "vStack", LazyHStack: "hStack",
        LazyHGrid: "hStack", ControlGroup: "controlGroup", Toolbar: "group", ToolbarItem: "group",
        Label: "label", Menu: "menu", Link: "link", Toggle: "toggle", Picker: "picker",
        Slider: "slider", DisclosureGroup: "disclosureGroup", BarChart: "barChart", Chart: "chart",
        RoundedRectangle: "roundedRectangle", Rectangle: "rectangle", Capsule: "capsule",
        Circle: "circle", ContentUnavailableView: "contentUnavailableView", EmptyView: "group", Markdown: "markdown",
        SVG: "svg",
        LiveActivityUI: "liveActivityUI",
        LiveActivityUIExpandedLeading: "liveActivityExpandedLeading",
        LiveActivityUIExpandedTrailing: "liveActivityExpandedTrailing",
        LiveActivityUIExpandedCenter: "liveActivityExpandedCenter",
        LiveActivityUIExpandedBottom: "liveActivityExpandedBottom"
      });

      function flatten(value, output = []) {
        if (Array.isArray(value)) value.forEach(item => flatten(item, output));
        else if (value !== null && value !== undefined && value !== false && value !== true) output.push(value);
        return output;
      }

      function component(type, properties, children) {
        return { __hanlinComponent: true, type, properties, children };
      }

      function createElement(type, properties, ...children) {
        const props = properties == null ? {} : { ...properties };
        const normalizedChildren = flatten(children);
        props.children = normalizedChildren.length === 1 ? normalizedChildren[0] : normalizedChildren;
        if (type === Fragment) return normalizedChildren;
        if (typeof type !== "function") throw new TypeError("HANLIN_UI:invalid_component");
        if (type.__hanlinKind) return {
          __hanlinHost: true, kind: type.__hanlinKind, hostName: type.__hanlinName,
          properties: props, children: normalizedChildren
        };
        return component(type, props, normalizedChildren);
      }

      function Fragment(properties) { return properties?.children ?? []; }

      for (const [name, kind] of Object.entries(hostKinds)) {
        const marker = function HanlinHostComponent() {};
        Object.defineProperty(marker, "__hanlinKind", { value: kind });
        Object.defineProperty(marker, "__hanlinName", { value: name });
        Object.defineProperty(globalThis, name, { configurable: false, enumerable: true, value: marker });
      }

      function nextState(initialValue) {
        const index = hookCursor++;
        if (!(index in state)) state[index] = typeof initialValue === "function" ? initialValue() : initialValue;
        return index;
      }

      function useState(initialValue) {
        const index = nextState(initialValue);
        return [state[index], value => {
          const next = typeof value === "function" ? value(state[index]) : value;
          if (Object.is(next, state[index])) return;
          state[index] = next;
          requestRender();
        }];
      }

      function useObservable(initialValue) {
        const index = hookCursor++;
        if (!(index in state)) state[index] = {
          value: typeof initialValue === "function" ? initialValue() : initialValue,
          subscribers: new Set()
        };
        const observableState = state[index];
        return Object.freeze({
          __hanlinObservable: true,
          get value() { return observableState.value; },
          setValue(value) {
            const next = typeof value === "function" ? value(observableState.value) : value;
            if (Object.is(next, observableState.value)) return;
            observableState.value = next;
            for (const subscriber of [...observableState.subscribers]) subscriber(next);
            requestRender();
          },
          subscribe(subscriber) {
            if (typeof subscriber !== "function") throw new TypeError("HANLIN_UI:observable_subscriber");
            observableState.subscribers.add(subscriber);
          },
          unsubscribe(subscriber) { observableState.subscribers.delete(subscriber); }
        });
      }

      function useRef(initialValue) {
        const index = nextState({ current: initialValue });
        return state[index];
      }

      function dependenciesChanged(left, right) {
        return !left || left.length !== right.length || right.some((value, index) => !Object.is(value, left[index]));
      }

      function useMemo(factory, dependencies = []) {
        const index = nextState(null);
        const previous = state[index];
        if (!previous || dependenciesChanged(previous.dependencies, dependencies)) {
          state[index] = { dependencies: [...dependencies], value: factory() };
        }
        return state[index].value;
      }

      function useCallback(callback, dependencies = []) { return useMemo(() => callback, dependencies); }

      function useReducer(reducer, initialState, initializer = undefined) {
        if (typeof reducer !== "function") throw new TypeError("HANLIN_UI:invalid_reducer");
        const index = hookCursor++;
        if (!(index in state)) {
          const reducerState = {
            value: typeof initializer === "function" ? initializer(initialState) : initialState,
            reducer,
            dispatch: null
          };
          reducerState.dispatch = action => {
            const next = reducerState.reducer(reducerState.value, action);
            if (Object.is(next, reducerState.value)) return;
            reducerState.value = next;
            requestRender();
          };
          state[index] = reducerState;
        }
        state[index].reducer = reducer;
        return [state[index].value, state[index].dispatch];
      }

      function useEffect(setup, dependencies = []) {
        const index = hookCursor++;
        const previous = effects.get(index);
        if (dependenciesChanged(previous?.dependencies, dependencies)) {
          previous?.dispose?.();
          const dispose = setup();
          effects.set(index, { dependencies: [...dependencies], dispose: typeof dispose === "function" ? dispose : null });
        }
      }

      function useEffectEvent(callback) { return (...argumentsList) => callback(...argumentsList); }
      function createContext(defaultValue) {
        const id = Symbol("HanlinContext");
        contexts.set(id, defaultValue);
        return Object.freeze({
          __hanlinContext: id,
          Provider: ({ value, children }) => { contexts.set(id, value); return children; }
        });
      }
      function useContext(context) { return contexts.get(context.__hanlinContext); }

      function registerHandler(callback) {
        const id = `event-${handlerCursor++}`;
        handlers.set(id, callback);
        return id;
      }

      function sanitize(value, depth = 0) {
        if (depth > 64) throw new TypeError("HANLIN_UI:property_depth");
        if (value === undefined || value === null) return null;
        if (typeof value === "function") return registerHandler(value);
        if (typeof value === "string" || typeof value === "boolean") return value;
        if (typeof value === "number") {
          if (!Number.isFinite(value)) throw new TypeError("HANLIN_UI:non_finite_number");
          return value;
        }
        if (typeof value === "bigint") return value.toString();
        if (value.__hanlinObservable) return sanitize(value.value, depth + 1);
        if (value instanceof Date) return value.toISOString();
        if (Array.isArray(value)) return value.map(item => sanitize(item, depth + 1));
        if (value.__hanlinComponent || value.__hanlinHost) return null;
        const output = {};
        for (const [key, member] of Object.entries(value)) output[key] = sanitize(member, depth + 1);
        return output;
      }

      function materialize(value) {
        if (value === null || value === undefined || value === false || value === true) return [];
        if (Array.isArray(value)) return flatten(value.map(materialize));
        if (typeof value === "string" || typeof value === "number" || typeof value === "bigint") {
          return [{ kind: "text", key: null, properties: { text: String(value) }, children: [] }];
        }
        if (value.__hanlinComponent) return materialize(value.type(value.properties));
        if (!value.__hanlinHost) throw new TypeError("HANLIN_UI:invalid_node");
        if (value.hostName === "NavigationDestination") {
          const builder = value.children.find(child => typeof child === "function");
          if (typeof builder === "function") navigationDestinationBuilders.push(builder);
          return [];
        }
        const configuredDestination = value.properties.navigationDestination;
        if (configuredDestination?.__hanlinHost
            && configuredDestination.hostName === "NavigationDestination") {
          const builder = configuredDestination.children.find(child => typeof child === "function");
          if (typeof builder === "function") navigationDestinationBuilders.push(builder);
        }
        let children = value.kind === "scrollViewReader"
          ? []
          : flatten(value.children.map(materialize));
        if (value.hostName === "Section") {
          children = [
            ...materialize(value.properties.header),
            ...children,
            ...materialize(value.properties.footer)
          ];
        }
        const properties = {};
        for (const [key, member] of Object.entries(value.properties)) {
          if (key !== "children") properties[key] = sanitize(member);
        }
        if (value.kind === "text" && properties.text == null) {
          properties.text = children.filter(child => child.kind === "text").map(child => child.properties.text).join("");
        }
        if (value.kind === "button") {
          properties.onPress = properties.action ?? properties.onPress ?? properties.onChanged ?? null;
          properties.title = properties.title ?? properties.label ?? "";
        }
        if (value.kind === "link") properties.url = String(value.properties.url ?? "");
        if (value.kind === "toggle") {
          const source = value.properties.value ?? value.properties.isOn;
          const current = source?.__hanlinObservable ? source.value : source;
          properties.value = current === true;
          properties.onChange = registerHandler(next => {
            if (source?.__hanlinObservable) source.setValue(next);
            if (typeof value.properties.onChanged === "function") value.properties.onChanged(next);
          });
        }
        if (value.kind === "textField") properties.onChange = properties.onChanged ?? properties.onChange ?? null;
        if (value.kind === "label") {
          properties.title = properties.title ?? "";
          properties.systemImage = properties.systemImage ?? "circle";
        }
        if (value.kind === "picker") {
          const source = value.properties.value ?? value.properties.selection;
          const current = source?.__hanlinObservable ? source.value : source;
          properties.value = current == null ? "" : String(current);
          properties.onChange = registerHandler(selectedValue => {
            if (source?.__hanlinObservable) source.setValue(selectedValue);
            if (typeof value.properties.onChanged === "function") value.properties.onChanged(selectedValue);
          });
        }
        if (value.kind === "contentUnavailableView") {
          const labelNodes = materialize(value.properties.label);
          const descriptionNodes = materialize(value.properties.description);
          const actionNodes = materialize(value.properties.actions);
          properties.labelCount = labelNodes.length;
          properties.descriptionCount = descriptionNodes.length;
          properties.actionCount = actionNodes.length;
          children = [...labelNodes, ...descriptionNodes, ...actionNodes, ...children];
        }
        if (value.kind === "groupBox") {
          const labelNodes = materialize(value.properties.label);
          properties.labelCount = labelNodes.length;
          children = [...labelNodes, ...children];
        }
        if (value.kind === "disclosureGroup") {
          const source = value.properties.isExpanded;
          const current = source?.__hanlinObservable ? source.value : source;
          const labelNodes = materialize(value.properties.label);
          properties.isExpanded = current === true;
          properties.labelCount = labelNodes.length;
          properties.onChange = registerHandler(next => {
            if (source?.__hanlinObservable) source.setValue(next);
            if (typeof value.properties.onChanged === "function") value.properties.onChanged(next);
          });
          children = [...labelNodes, ...children];
        }
        if (value.kind === "slider") {
          const source = value.properties.value;
          const current = source?.__hanlinObservable ? source.value : source;
          const labelNodes = materialize(value.properties.label);
          properties.value = Number(current ?? value.properties.min ?? 0);
          properties.labelCount = labelNodes.length;
          properties.onChange = registerHandler(next => {
            const number = Number(next);
            if (source?.__hanlinObservable) source.setValue(number);
            if (typeof value.properties.onChanged === "function") value.properties.onChanged(number);
          });
          properties.onEditingChange = typeof value.properties.onEditingChanged === "function"
            ? registerHandler(value.properties.onEditingChanged)
            : null;
          children = [...labelNodes, ...children];
        }
        if (value.kind === "navigationSplitView") {
          const visibility = value.properties.columnVisibility;
          const compactColumn = value.properties.preferredCompactColumn;
          const visibilityValue = visibility?.__hanlinObservable
            ? visibility.value : visibility?.value ?? visibility;
          const compactValue = compactColumn?.__hanlinObservable
            ? compactColumn.value : compactColumn?.value ?? compactColumn;
          const sidebarNodes = materialize(value.properties.sidebar);
          const contentNodes = materialize(value.properties.content);
          properties.columnVisibility = String(visibilityValue ?? "automatic");
          properties.preferredCompactColumn = String(compactValue ?? "detail");
          properties.sidebarCount = sidebarNodes.length;
          properties.contentCount = contentNodes.length;
          properties.onColumnVisibilityChange = registerHandler(next => {
            if (visibility?.__hanlinObservable) visibility.setValue(next);
            if (typeof visibility?.onChanged === "function") visibility.onChanged(next);
          });
          properties.onPreferredCompactColumnChange = registerHandler(next => {
            if (compactColumn?.__hanlinObservable) compactColumn.setValue(next);
            if (typeof compactColumn?.onChanged === "function") compactColumn.onChanged(next);
          });
          children = [...sidebarNodes, ...contentNodes, ...children];
        }
        if (value.kind === "scrollViewReader") {
          const builder = value.children.find(child => typeof child === "function");
          const proxy = Object.freeze({
            scrollTo(id, anchor = null) {
              scrollTarget = String(id);
              scrollAnchor = anchor == null ? null : String(anchor);
              scrollRevision += 1;
              requestRender();
            }
          });
          children = typeof builder === "function" ? materialize(builder(proxy)) : children;
          properties.scrollTarget = scrollTarget;
          properties.scrollAnchor = scrollAnchor;
          properties.scrollRevision = scrollRevision;
        }
        if (value.kind === "svg") {
          if (typeof value.properties.code === "string") {
            properties.code = value.properties.code;
          } else if (typeof value.properties.filePath === "string") {
            properties.code = FileManager.readAsStringSync(value.properties.filePath);
          } else {
            throw new TypeError("HANLIN_UI:svg_source");
          }
          if (properties.code.length > 2 * 1024 * 1024) {
            throw new TypeError("HANLIN_UI:svg_size");
          }
        }
        if (value.kind === "liveActivityUI") {
          const region = (kind, configured) => ({
            kind, key: null, properties: {}, children: materialize(configured)
          });
          children = [
            region("liveActivityContent", value.properties.content),
            region("liveActivityCompactLeading", value.properties.compactLeading),
            region("liveActivityCompactTrailing", value.properties.compactTrailing),
            region("liveActivityMinimal", value.properties.minimal),
            ...children
          ];
        }
        const routeDefinitions = [];
        if (value.kind === "navigationLink") {
          const route = value.properties.value == null
            ? `destination-${handlerCursor++}`
            : String(value.properties.value);
          const destination = value.properties.destination;
          const builder = navigationDestinationBuilders.at(-1);
          const destinationNodes = destination != null
            ? materialize(destination)
            : typeof builder === "function" && value.properties.value != null
              ? materialize(builder(String(value.properties.value)))
              : [];
          properties.route = route;
          if (destinationNodes.length > 0) {
            routeDefinitions.push({
              kind: "navigationDestination", key: `route-${route}`,
              properties: { route }, children: destinationNodes
            });
          }
        }
        if (value.kind === "navigationStack") {
          const source = value.properties.path;
          const path = source?.__hanlinObservable ? source.value : source;
          properties.path = Array.isArray(path) ? path.map(String) : [];
          properties.onPathChange = registerHandler(nextPath => {
            const normalized = Array.isArray(nextPath) ? nextPath.map(String) : [];
            if (source?.__hanlinObservable) source.setValue(normalized);
          });
          const builder = navigationDestinationBuilders.at(-1);
          if (typeof builder === "function") {
            for (const route of properties.path) {
              const destinationNodes = materialize(builder(route));
              if (destinationNodes.length > 0) {
                routeDefinitions.push({
                  kind: "navigationDestination", key: `route-${route}`,
                  properties: { route }, children: destinationNodes
                });
              }
            }
          }
        }
        if (value.kind === "tabView" && value.properties.selection?.__hanlinObservable) {
          properties.onChange = registerHandler(selectedValue => {
            const current = value.properties.selection.value;
            value.properties.selection.setValue(
              typeof current === "number" ? Number(selectedValue) : selectedValue
            );
          });
        }
        if (value.kind === "tab") properties.id = String(properties.value ?? properties.id ?? properties.title ?? "tab");
        const node = {
          kind: value.kind,
          key: value.properties.key == null ? null : String(value.properties.key),
          properties,
          children
        };
        const presentations = [];
        for (const [propertyName, style, contentName] of [
          ["sheet", "sheet", "content"],
          ["fullScreenCover", "fullScreen", "content"],
          ["confirmationDialog", "dialog", "actions"]
        ]) {
          const configured = value.properties[propertyName];
          const candidates = Array.isArray(configured) ? configured : configured ? [configured] : [];
          const active = candidates.find(candidate => {
            const presented = candidate?.isPresented;
            return presented?.__hanlinObservable ? presented.value === true : presented === true;
          });
          if (active) {
            const onDismiss = registerHandler(() => {
              if (active.isPresented?.__hanlinObservable) active.isPresented.setValue(false);
              if (typeof active.onChanged === "function") active.onChanged(false);
            });
            presentations.push({
              kind: "presentation", key: null,
              properties: {
                id: `${style}-${onDismiss}`, style, onDismiss,
                title: active.title ?? "", message: active.message ?? ""
              },
              children: materialize(active[contentName])
            });
            break;
          }
        }
        return [node, ...routeDefinitions, ...presentations];
      }

      function render() {
        if (rendering || presentedElement == null) { renderPending = true; return; }
        rendering = true;
        try {
          hookCursor = 0;
          handlerCursor = 0;
          handlers.clear();
          navigationDestinationBuilders = [];
          const nodes = materialize(presentedElement);
          const root = nodes.length === 1 ? nodes[0] : { kind: "fragment", key: null, properties: {}, children: nodes };
          __hanlinNativeRender(JSON.stringify(root));
        } finally {
          rendering = false;
          if (renderPending && !renderScheduled) {
            renderScheduled = true;
            queueMicrotask(() => {
              renderScheduled = false;
              if (!renderPending) return;
              renderPending = false;
              render();
            });
          }
        }
      }

      function requestRender() {
        if (rendering) { renderPending = true; return; }
        render();
      }

      function ForEach(properties) {
        const source = properties.data ?? properties.values ?? [];
        const data = source?.__hanlinObservable ? source.value : source;
        const builder = properties.builder ?? properties.children;
        if (!Array.isArray(data) || typeof builder !== "function") return [];
        return data.map((item, index) => builder(item, index));
      }

      const Navigation = Object.freeze({
        present(options) {
          globalThis.__hanlinHasPresentedUI = true;
          presentedElement = options && Object.hasOwn(options, "element") ? options.element : options;
          render();
          return new Promise(resolve => { dismissPresentation = resolve; });
        },
        useDismiss() { return value => { dismissPresentation?.(value); dismissPresentation = null; }; }
      });
      const Storage = Object.freeze({
        get(key, options = {}) {
          const response = JSON.parse(__hanlinNativeStorageGet(String(key), options.shared === true));
          if (!response.allowed) throw new Error("HANLIN_PERMISSION:storage");
          return response.found ? JSON.parse(response.json) : null;
        },
        set(key, value, options = {}) {
          if (!__hanlinNativeStorageSet(String(key), JSON.stringify(value), options.shared === true)) throw new Error("HANLIN_STORAGE:write_failed");
          return true;
        },
        remove(key, options = {}) {
          if (!__hanlinNativeStorageRemove(String(key), options.shared === true)) throw new Error("HANLIN_STORAGE:remove_failed");
        },
        contains(key, options = {}) { return __hanlinNativeStorageContains(String(key), options.shared === true); },
        keys(options = {}) {
          const response = JSON.parse(__hanlinNativeStorageKeys(options.shared === true));
          if (!response.allowed) throw new Error("HANLIN_PERMISSION:storage");
          return response.keys;
        },
        getData(key, options = {}) {
          const response = JSON.parse(__hanlinNativeStorageGetData(String(key), options.shared === true));
          if (!response.allowed) throw new Error("HANLIN_PERMISSION:storage");
          return response.found ? HanlinData.fromBase64String(response.base64) : null;
        },
        setData(key, value, options = {}) {
          const data = value instanceof HanlinData ? value : new HanlinData(value);
          if (!__hanlinNativeStorageSetData(String(key), data.toBase64String(), options.shared === true)) throw new Error("HANLIN_STORAGE:write_failed");
        },
        clear() { if (!__hanlinNativeStorageClear()) throw new Error("HANLIN_STORAGE:clear_failed"); }
      });
      const Assistant = Object.freeze({
        get isAvailable() {
          return typeof __hanlinNativeAssistantAvailable === "function"
            ? __hanlinNativeAssistantAvailable()
            : Boolean(__hanlinNativeAssistantAvailable);
        },
        isPresented: false,
        hasActiveConversation: false,
        requestStreaming(options) {
          if (!this.isAvailable) return Promise.reject(new Error("Assistant is not available"));
          try {
            if (!options || typeof options !== "object") throw new TypeError("Assistant options are required");
            const systemPrompt = options.systemPrompt == null ? null : String(options.systemPrompt);
            const messages = normalizeAssistantMessages(options.messages);
            const provider = normalizeAssistantProvider(options.provider);
            const modelId = options.modelId == null ? null : String(options.modelId);
            return Promise.resolve(startAssistantStream({
              kind: "streaming", systemPrompt, messages, provider, modelId
            }));
          } catch (error) { return Promise.reject(error); }
        },
        requestStructuredData(prompt, imagesOrSchema, schemaOrOptions, maybeOptions) {
          if (!this.isAvailable) return Promise.reject(new Error("Assistant is not available"));
          try {
            if (typeof prompt !== "string" || prompt.length === 0) {
              throw new TypeError("A non-empty Assistant prompt is required");
            }
            const hasImages = Array.isArray(imagesOrSchema);
            const images = hasImages ? imagesOrSchema : [];
            const schema = hasImages ? schemaOrOptions : imagesOrSchema;
            const options = (hasImages ? maybeOptions : schemaOrOptions) ?? {};
            if (!images.every(image => typeof image === "string"
                && image.startsWith("data:image/") && image.includes(";base64,"))) {
              throw new TypeError("Assistant images must be data URIs");
            }
            validateAssistantSchema(schema);
            const stream = startAssistantStream({
              kind: "structured_data",
              prompt,
              images,
              schema,
              provider: normalizeAssistantProvider(options.provider),
              modelId: options.modelId == null ? null : String(options.modelId)
            });
            return (async () => {
              let result;
              for await (const chunk of stream) {
                if (chunk?.type !== "structured" || result !== undefined) {
                  await stream.return();
                  throw new TypeError("The Assistant returned an invalid structured response");
                }
                result = chunk.content;
              }
              if (result === undefined) throw new TypeError("The Assistant returned no structured response");
              return result;
            })();
          } catch (error) { return Promise.reject(error); }
        },
        startConversation() {
          return Promise.reject(new Error("Assistant conversation UI is not available"));
        },
        present() { return Promise.reject(new Error("Assistant conversation UI is not available")); },
        dismiss() { return Promise.resolve(); },
        stopConversation() { return Promise.resolve(); }
      });
      let sqliteHandleCursor = 0;
      function sqliteArguments(value) {
        if (value == null) return null;
        if (value instanceof Date) return value.getTime();
        if (value instanceof HanlinData) return value.toBase64String();
        if (Array.isArray(value)) return value.map(sqliteArguments);
        if (typeof value === "object") {
          const output = {};
          for (const [key, member] of Object.entries(value)) output[key] = sqliteArguments(member);
          return output;
        }
        if (["string", "number", "boolean"].includes(typeof value)) return value;
        throw new TypeError("Unsupported SQLite argument type");
      }
      function reviveSQLite(value) {
        if (Array.isArray(value)) return value.map(reviveSQLite);
        if (value && typeof value === "object") {
          if (typeof value.__hanlinSQLiteData === "string") return HanlinData.fromBase64String(value.__hanlinSQLiteData);
          const output = {};
          for (const [key, member] of Object.entries(value)) output[key] = reviveSQLite(member);
          return output;
        }
        return value;
      }
      class HanlinSQLiteDatabase {
        constructor(path, configuration) {
          this.path = path;
          this.configuration = configuration;
          this.handle = `sqlite-${++sqliteHandleCursor}`;
        }
        _call(operation, sql, argumentsValue) {
          if (typeof sql !== "string" || sql.length === 0) return Promise.reject(new TypeError("SQL is required"));
          return nativeCallAsync(operation, {
            handle: this.handle, path: this.path, configuration: this.configuration,
            sql, arguments: sqliteArguments(argumentsValue)
          }).then(reviveSQLite);
        }
        execute(sql, argumentsValue = null) { return this._call("sqlite.execute", sql, argumentsValue); }
        fetchAll(sql, argumentsValue = null) { return this._call("sqlite.fetchAll", sql, argumentsValue); }
        fetchSet(sql, argumentsValue = null) { return this.fetchAll(sql, argumentsValue); }
        async fetchOne(sql, argumentsValue = null) {
          const rows = await this.fetchAll(sql, argumentsValue);
          if (rows.length === 0) throw new Error("SQLite query returned no rows");
          return rows[0];
        }
        async transaction(steps) {
          const values = Array.isArray(steps) ? steps : [steps];
          await this.execute("BEGIN IMMEDIATE");
          try {
            for (const step of values) await this.execute(step.sql, step.args ?? null);
            await this.execute("COMMIT");
          } catch (error) {
            try { await this.execute("ROLLBACK"); } catch {}
            throw error;
          }
        }
      }
      const SQLite = Object.freeze({
        open(path, configuration = {}) {
          return new HanlinSQLiteDatabase(normalizePath(path), {
            foreignKeysEnabled: configuration.foreignKeysEnabled === true,
            readonly: configuration.readonly === true,
            label: configuration.label == null ? null : String(configuration.label),
            busyMode: typeof configuration.busyMode === "number" ? configuration.busyMode : "immediateError",
            journalMode: configuration.journalMode === "wal" ? "wal" : "default",
            maximumReaderCount: Number(configuration.maximumReaderCount ?? 1)
          });
        },
        openInMemory(name = "default", configuration = {}) {
          return new HanlinSQLiteDatabase(`:memory:${String(name)}`, configuration);
        }
      });
      const liveActivityBuilders = new Map();
      class HanlinLiveActivity {
        constructor(name, builder, activityId = null) {
          this.name = name;
          this.builder = builder;
          this._activityId = activityId;
          this._started = activityId != null;
          this._updateListeners = new Set();
        }
        get activityId() { return this._activityId ?? undefined; }
        get started() { return this._started; }
        _payload(state, options = {}) {
          const nodes = materialize(this.builder(state));
          if (nodes.length !== 1 || nodes[0].kind !== "liveActivityUI") {
            throw new TypeError("A Live Activity builder must return LiveActivityUI");
          }
          return { name: this.name, activityId: this._activityId, state, root: nodes[0], options };
        }
        async start(state, options = {}) {
          if (this._started) return false;
          const result = await nativeCallAsync("liveActivity.start", this._payload(state, options));
          if (!result || typeof result.activityId !== "string" || result.activityId.length === 0) return false;
          this._activityId = result.activityId;
          this._started = true;
          this._notify("active");
          return true;
        }
        async update(state, options = {}) {
          if (!this._started || !this._activityId) return false;
          const result = await nativeCallAsync("liveActivity.update", this._payload(state, options));
          if (result === true) this._notify("active");
          return result === true;
        }
        async end(state, options = {}) {
          if (!this._started || !this._activityId) return false;
          const result = await nativeCallAsync("liveActivity.end", this._payload(state, options));
          if (result === true) {
            this._started = false;
            this._notify("ended");
          }
          return result === true;
        }
        getActivityState() { return Promise.resolve(this._started ? "active" : this._activityId ? "ended" : null); }
        addUpdateListener(listener) {
          if (typeof listener !== "function") throw new TypeError("A Live Activity listener must be a function");
          this._updateListeners.add(listener);
        }
        removeUpdateListener(listener) { this._updateListeners.delete(listener); }
        _notify(state) { for (const listener of [...this._updateListeners]) listener(state); }
      }
      const LiveActivity = Object.freeze({
        register(name, builder) {
          if (typeof name !== "string" || name.length === 0 || name.length > 256 || typeof builder !== "function") {
            throw new TypeError("A Live Activity name and builder are required");
          }
          liveActivityBuilders.set(name, builder);
          return () => new HanlinLiveActivity(name, builder);
        },
        areActivitiesEnabled() {
          return nativeCallAsync("liveActivity.areActivitiesEnabled").then(Boolean, () => false);
        },
        from(activityId, name) {
          const builder = liveActivityBuilders.get(name);
          return Promise.resolve(builder && activityId ? new HanlinLiveActivity(name, builder, String(activityId)) : null);
        },
        getActivityState() { return Promise.resolve(null); },
        getAllActivities() { return Promise.resolve([]); },
        getAllActivitiesIds() { return Promise.resolve([]); },
        endAllActivities() { return Promise.resolve(false); },
        addActivitiesEnabledListener() {}, removeActivitiesEnabledListener() {},
        addActivityUpdateListener() {}, removeActivityUpdateListener() {}
      });
      const Script = Object.freeze({
        name: "Hanlin Scripting App", directory: FileManager.scriptsDirectory,
        queryParameters: {}, shareFiles: [],
        exit() {}, minimize() {}, onResume() { return () => {}; }
      });
      const deviceSnapshot = globalThis.__hanlinNativeDeviceSnapshot ?? {};
      const Device = Object.freeze({
        ...deviceSnapshot,
        screen: Object.freeze({ ...(deviceSnapshot.screen ?? {}) }),
        preferredLanguages: Object.freeze([...(deviceSnapshot.preferredLanguages ?? [])]),
        systemLocales: Object.freeze([...(deviceSnapshot.systemLocales ?? [])])
      });
      function pasteboardCall(operation, payload = {}) {
        return nativeCallAsync(`pasteboard.${operation}`, payload);
      }
      const Pasteboard = Object.freeze({
        get changeCount() { return pasteboardCall("changeCount"); },
        get hasStrings() { return pasteboardCall("hasStrings"); },
        get hasImages() { return pasteboardCall("hasImages"); },
        get hasURLs() { return pasteboardCall("hasURLs"); },
        get numberOfItems() { return pasteboardCall("numberOfItems"); },
        getString() { return pasteboardCall("getString"); },
        setString(value) {
          if (value != null && typeof value !== "string") return Promise.reject(new TypeError("Pasteboard string must be a string or null"));
          return pasteboardCall("setString", { value });
        },
        getStrings() { return pasteboardCall("getStrings"); },
        setStrings(value) {
          if (value != null && (!Array.isArray(value) || value.some(item => typeof item !== "string"))) {
            return Promise.reject(new TypeError("Pasteboard strings must be an array of strings or null"));
          }
          return pasteboardCall("setStrings", { value });
        },
        getURL() { return pasteboardCall("getURL"); },
        setURL(value) {
          if (value != null && typeof value !== "string") return Promise.reject(new TypeError("Pasteboard URL must be a string or null"));
          return pasteboardCall("setURL", { value });
        },
        getURLs() { return pasteboardCall("getURLs"); },
        setURLs(value) {
          if (value != null && (!Array.isArray(value) || value.some(item => typeof item !== "string"))) {
            return Promise.reject(new TypeError("Pasteboard URLs must be an array of strings or null"));
          }
          return pasteboardCall("setURLs", { value });
        },
        getImage() { return Promise.reject(new Error("Pasteboard images are not yet available")); },
        setImage() { return Promise.reject(new Error("Pasteboard images are not yet available")); },
        getImages() { return Promise.reject(new Error("Pasteboard images are not yet available")); },
        setImages() { return Promise.reject(new Error("Pasteboard images are not yet available")); },
        addItems() { return Promise.reject(new Error("Typed Pasteboard items are not yet available")); },
        setItems() { return Promise.reject(new Error("Typed Pasteboard items are not yet available")); },
        getItems() { return Promise.reject(new Error("Typed Pasteboard items are not yet available")); },
        onChanged: null,
        onRemoved: null
      });
      const DocumentPicker = Object.freeze({
        pickFiles(options = {}) {
          if (options == null || typeof options !== "object" || Array.isArray(options)) {
            return Promise.reject(new TypeError("DocumentPicker options must be an object"));
          }
          return nativeCallAsync("documentPicker.pickFiles", {
            allowsMultipleSelection: options.allowsMultipleSelection ?? false,
            shouldShowFileExtensions: options.shouldShowFileExtensions ?? true,
            types: options.types ?? []
          });
        },
        pickDirectory(initialDirectory = null) {
          if (initialDirectory != null && typeof initialDirectory !== "string") {
            return Promise.reject(new TypeError("DocumentPicker initialDirectory must be a string or null"));
          }
          return nativeCallAsync("documentPicker.pickDirectory", { initialDirectory });
        },
        stopAcessingSecurityScopedResources() {
          nativeCallAsync("documentPicker.stopAccessingSecurityScopedResources", {}).catch(() => {});
        },
        pickFileBookmark() { return Promise.reject(new Error("DocumentPicker bookmarks are not supported yet")); },
        pickDirectoryBookmark() { return Promise.reject(new Error("DocumentPicker bookmarks are not supported yet")); },
        exportFiles() { return Promise.reject(new Error("DocumentPicker export is not supported yet")); }
      });
      const QuickLook = Object.freeze({
        previewURLs(urls, fullscreen = false) {
          if (!Array.isArray(urls) || urls.some(url => typeof url !== "string") || typeof fullscreen !== "boolean") {
            return Promise.reject(new TypeError("QuickLook.previewURLs requires URL strings and a Boolean fullscreen value"));
          }
          return nativeCallAsync("quickLook.previewURLs", { urls, fullscreen });
        },
        previewText(text, fullscreen = false) {
          if (typeof text !== "string" || typeof fullscreen !== "boolean") {
            return Promise.reject(new TypeError("QuickLook.previewText requires text and a Boolean fullscreen value"));
          }
          return nativeCallAsync("quickLook.previewText", { text, fullscreen });
        },
        previewImage(image, fullscreen = false) {
          if (!(image instanceof HanlinUIImage) || typeof fullscreen !== "boolean") {
            return Promise.reject(new TypeError("QuickLook.previewImage requires a UIImage and a Boolean fullscreen value"));
          }
          return nativeCallAsync("quickLook.previewImage", {
            base64: image.toBase64String(), fullscreen
          });
        }
      });
      const Photos = Object.freeze({
        pickPhotos(count) {
          if (!Number.isInteger(count) || count < 1 || count > 100) {
            return Promise.reject(new TypeError("Photos.pickPhotos count must be an integer from 1 through 100"));
          }
          return nativeCallAsync("photos.pickPhotos", { count }).then(values =>
            values.map(value => HanlinUIImage.fromBase64String(value)).filter(Boolean)
          );
        },
        takePhoto() {
          return nativeCallAsync("photos.takePhoto", {}).then(value =>
            value == null ? null : HanlinUIImage.fromBase64String(value)
          );
        }
      });
      function normalizedDialogInput(input, prompt = false) {
        if (typeof input === "string") return prompt ? { title: input } : { message: input };
        if (!input || typeof input !== "object" || Array.isArray(input)) {
          throw new TypeError("Dialog options must be a string or object");
        }
        return { ...input };
      }
      const Dialog = Object.freeze({
        alert(input) {
          try { return nativeCallAsync("dialog.alert", normalizedDialogInput(input)); }
          catch (error) { return Promise.reject(error); }
        },
        confirm(input) {
          try { return nativeCallAsync("dialog.confirm", normalizedDialogInput(input)).then(Boolean); }
          catch (error) { return Promise.reject(error); }
        },
        prompt(input) {
          try { return nativeCallAsync("dialog.prompt", normalizedDialogInput(input, true)); }
          catch (error) { return Promise.reject(error); }
        },
        actionSheet(input) {
          try { return nativeCallAsync("dialog.actionSheet", normalizedDialogInput(input)); }
          catch (error) { return Promise.reject(error); }
        }
      });
      class EditorController {
        constructor(options = {}) {
          if (!options || typeof options !== "object" || Array.isArray(options)) {
            throw new TypeError("EditorController options must be an object");
          }
          const content = options.content ?? "";
          const ext = options.ext ?? "txt";
          if (typeof content !== "string" || content.length > 4 * 1024 * 1024
              || !["tsx", "ts", "js", "jsx", "txt", "md", "css", "html", "json"].includes(ext)
              || (options.readOnly != null && typeof options.readOnly !== "boolean")) {
            throw new TypeError("EditorController options are invalid");
          }
          this.ext = ext;
          this.readOnly = options.readOnly ?? false;
          this._content = content;
          this._selection = { start: 0, end: 0 };
          this._disposed = false;
          this._presentPromise = null;
          this._abortController = null;
          this._dismissRequested = false;
          this.onContentChanged = undefined;
        }
        get content() { return this._content; }
        set content(value) {
          if (this._disposed) throw new Error("EditorController has been disposed");
          if (typeof value !== "string" || value.length > 4 * 1024 * 1024) {
            throw new TypeError("Editor content must be a bounded string");
          }
          this._content = value;
          this._selection = { start: Math.min(this._selection.start, value.length), end: Math.min(this._selection.end, value.length) };
        }
        present(options = {}) {
          if (this._disposed) return Promise.reject(new Error("EditorController has been disposed"));
          if (this._presentPromise) return Promise.reject(new Error("EditorController is already presented"));
          if (!options || typeof options !== "object" || Array.isArray(options)
              || (options.fullscreen != null && typeof options.fullscreen !== "boolean")) {
            return Promise.reject(new TypeError("Editor presentation options are invalid"));
          }
          this._dismissRequested = false;
          this._abortController = new HanlinAbortController();
          const before = this._content;
          const request = nativeCallAsync("editor.present", {
            content: before,
            ext: this.ext,
            readOnly: this.readOnly,
            navigationTitle: options.navigationTitle ?? null,
            scriptName: options.scriptName ?? null,
            fullscreen: options.fullscreen ?? false
          }, this._abortController.signal).then(content => {
            this._content = content;
            if (content !== before && typeof this.onContentChanged === "function") this.onContentChanged(content);
          }).catch(error => {
            if (this._dismissRequested && error?.name === "AbortError") return;
            throw error;
          }).finally(() => {
            this._presentPromise = null;
            this._abortController = null;
            this._dismissRequested = false;
          });
          this._presentPromise = request;
          return request;
        }
        dismiss() {
          if (!this._presentPromise) return Promise.resolve();
          this._dismissRequested = true;
          this._abortController.abort();
          return this._presentPromise;
        }
        dispose() {
          if (this._disposed) return;
          this._disposed = true;
          if (this._presentPromise) {
            this._dismissRequested = true;
            this._abortController.abort();
          }
          this.onContentChanged = undefined;
        }
        appendContent(text) {
          if (typeof text !== "string") throw new TypeError("Editor text must be a string");
          this.content = this._content + text;
        }
        selectAll() { this._selection = { start: 0, end: this._content.length }; }
        setSelection(start, end) {
          if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end < start || end > this._content.length) {
            throw new RangeError("Editor selection is invalid");
          }
          this._selection = { start, end };
        }
        getSelectedText() {
          if (this._disposed) return Promise.reject(new Error("EditorController has been disposed"));
          return Promise.resolve(this._content.slice(this._selection.start, this._selection.end));
        }
        replaceSelection(text) {
          if (typeof text !== "string") throw new TypeError("Editor replacement must be a string");
          const { start, end } = this._selection;
          this.content = this._content.slice(0, start) + text + this._content.slice(end);
          this._selection = { start: start + text.length, end: start + text.length };
        }
        searchText(query, options = {}) {
          if (typeof query !== "string" || !options || typeof options !== "object") {
            return Promise.reject(new TypeError("Editor search is invalid"));
          }
          try {
            const escaped = options.regexp ? query : query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            const source = options.wholeWord ? `\\b(?:${escaped})\\b` : escaped;
            const expression = new RegExp(source, options.caseSensitive ? "g" : "gi");
            const ranges = [];
            let match;
            while ((match = expression.exec(this._content)) !== null) {
              const start = match.index; const end = start + match[0].length;
              ranges.push({ start, end, line: this._content.slice(0, start).split("\n").length });
              if (match[0].length === 0) expression.lastIndex += 1;
            }
            return Promise.resolve(ranges);
          } catch (error) { return Promise.reject(error); }
        }
        scrollToLine() { throw new Error("Editor viewport control is unavailable"); }
        scrollToPosition() { throw new Error("Editor viewport control is unavailable"); }
        scrollSelectionIntoView() { throw new Error("Editor viewport control is unavailable"); }
        undo() { throw new Error("Editor undo is unavailable"); }
        redo() { throw new Error("Editor redo is unavailable"); }
        toggleLineComment() { throw new Error("Editor comment toggling is unavailable"); }
        toggleBlockComment() { throw new Error("Editor comment toggling is unavailable"); }
      }
      const Safari = Object.freeze({
        openURL(url) {
          if (typeof url !== "string" || url.length === 0 || url.length > 8192) {
            return Promise.reject(new TypeError("Safari.openURL requires a bounded URL string"));
          }
          return nativeCallAsync("safari.openURL", { url }).then(Boolean);
        },
        present() { return Promise.reject(new Error("In-app Safari presentation is not yet available")); }
      });
      const appIntentRegistrations = new Map();
      const Widget = Object.freeze({
        family: typeof globalThis.__hanlinNativeWidgetFamily === "string"
          ? globalThis.__hanlinNativeWidgetFamily : "systemMedium",
        widgetParameter: typeof globalThis.__hanlinNativeWidgetParameter === "string"
          ? globalThis.__hanlinNativeWidgetParameter : "",
        reloadAll() { globalThis.__hanlinNativeWidgetReloadAll?.(); },
        present(element, reloadPolicy = null) {
          if (globalThis.__hanlinNativeEntrypointKind !== "widget") {
            throw new Error("Widget.present is only available to a widget entrypoint");
          }
          const nodes = materialize(element);
          if (nodes.length !== 1) throw new TypeError("Widget.present requires exactly one root view");
          const date = reloadPolicy?.date;
          const reloadDate = date instanceof Date && Number.isFinite(date.getTime())
            ? date.getTime() : null;
          if (!globalThis.__hanlinNativeWidgetPresent(JSON.stringify({ root: nodes[0], reloadDate }))) {
            throw new Error("The widget presentation was rejected");
          }
        }
      });
      const AppIntentProtocol = Object.freeze({ AppIntent: "AppIntent" });
      const AppIntentManager = Object.freeze({
        register(options) {
          if (!options || typeof options.name !== "string" || typeof options.perform !== "function") {
            throw new TypeError("An App Intent name and perform function are required");
          }
          const protocolName = String(options.protocol ?? AppIntentProtocol.AppIntent);
          if (globalThis.__hanlinNativeEntrypointKind === "appIntent") {
            if (!globalThis.__hanlinNativeAppIntentRegister(JSON.stringify({
              name: options.name, protocol: protocolName
            }))) throw new Error("The App Intent registration was rejected");
            appIntentRegistrations.set(options.name, options.perform);
          } else if (globalThis.__hanlinNativeEntrypointKind !== "widget") {
            throw new Error("AppIntentManager.register is only available to Widget and App Intent entrypoints");
          }
          const factory = parameters => Object.freeze({
            __hanlinAppIntent: true,
            name: options.name,
            parameters: parameters ?? {}
          });
          Object.defineProperties(factory, {
            intentName: { value: options.name }, protocol: { value: protocolName }
          });
          return Object.freeze(factory);
        }
      });

      Object.assign(globalThis, {
        createElement, Fragment, useState, useObservable, useReducer, useRef, useMemo, useCallback,
        useEffect, useEffectEvent, createContext, useContext, ForEach, Navigation,
        Data: HanlinData, UIImage: HanlinUIImage, Path, FileManager, Headers: HanlinHeaders, Blob: HanlinBlob,
        FormData: HanlinFormData, Request: HanlinRequest, Response: HanlinResponse,
        fetch: hanlinFetch, DOMException: HanlinDOMException, AbortEvent: HanlinAbortEvent,
        AbortSignal: HanlinAbortSignal, AbortController: HanlinAbortController,
        Storage, SQLite, Assistant, Location, Health, HealthUnit, HealthStatistics,
        HealthActivitySummary, HealthWorkout,
        Notification, Reminder, DateComponents, CalendarNotificationTrigger, TimeIntervalNotificationTrigger,
        LiveActivity, Script, Device, Pasteboard, DocumentPicker, QuickLook, Photos, Dialog,
        EditorController, Safari,
        Widget, AppIntentProtocol, AppIntentManager,
        Color: Object.freeze({}),
        __hanlinResolveNative: resolveNativeRequest,
        __hanlinAssistantReceive: receiveAssistantChunk,
        __hanlinHasPresentedUI: false,
        __hanlinDispatch(handlerID, payloadJSON) {
          const handler = handlers.get(handlerID);
          if (typeof handler !== "function") throw new Error("HANLIN_UI:unknown_handler");
          const result = handler(JSON.parse(payloadJSON));
          Promise.resolve(result).catch(() => {});
        },
        __hanlinInvokeAppIntent(requestID, name, parametersJSON) {
          const perform = appIntentRegistrations.get(name);
          if (typeof perform !== "function") {
            __hanlinNativeAppIntentComplete(requestID, false, "The App Intent is not registered");
            return;
          }
          let parameters;
          try { parameters = JSON.parse(parametersJSON); }
          catch (error) {
            __hanlinNativeAppIntentComplete(requestID, false, String(error?.message ?? error));
            return;
          }
          Promise.resolve().then(() => perform(parameters)).then(
            value => __hanlinNativeAppIntentComplete(requestID, true, JSON.stringify(value ?? null)),
            error => __hanlinNativeAppIntentComplete(requestID, false, String(error?.message ?? error))
          );
        },
        __hanlinDismiss() { dismissPresentation?.(null); dismissPresentation = null; },
        __hanlinDispose() {
          for (const effect of effects.values()) effect.dispose?.();
          for (const [requestID, pending] of nativeRequests) {
            pending.signal?.removeEventListener("abort", pending.onAbort);
            __hanlinCancelNative(requestID);
            pending.reject(abortError("The scripting session was disposed."));
          }
          for (const [requestID, stream] of assistantStreams) {
            __hanlinCancelNative(requestID);
            stream.fail(abortError("The scripting session was disposed."));
          }
          nativeRequests.clear(); assistantStreams.clear(); effects.clear(); handlers.clear(); presentedElement = null;
        }
      });
    })();
    """#
}
