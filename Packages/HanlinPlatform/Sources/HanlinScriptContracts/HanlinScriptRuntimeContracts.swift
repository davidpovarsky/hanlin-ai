import Foundation
import HanlinPlatformContracts

public enum HanlinScriptSessionState: String, Codable, CaseIterable, Hashable, Sendable {
    case created
    case loading
    case active
    case suspended
    case closing
    case closed
    case failed
}

public struct HanlinScriptExecutionPolicy: Codable, Hashable, Sendable {
    public let schemaVersion: UInt32
    public let id: String
    public let context: HanlinExecutionContext
    public let memoryBytes: Int
    public let stackBytes: Int
    public let deadlineMilliseconds: UInt64
    public let maximumOutputBytes: Int
    public let maximumQueuedEvents: Int
    public let maximumPendingPromises: Int
    public let maximumCallbacks: Int
    public let maximumObjectHandles: Int
    public let maximumStorageBytes: Int64

    public init(
        schemaVersion: UInt32 = 1,
        id: String,
        context: HanlinExecutionContext,
        memoryBytes: Int,
        stackBytes: Int,
        deadlineMilliseconds: UInt64,
        maximumOutputBytes: Int,
        maximumQueuedEvents: Int,
        maximumPendingPromises: Int,
        maximumCallbacks: Int,
        maximumObjectHandles: Int,
        maximumStorageBytes: Int64
    ) throws {
        guard schemaVersion == 1, !id.isEmpty,
              memoryBytes > 0, stackBytes > 0, deadlineMilliseconds > 0,
              maximumOutputBytes > 0, maximumQueuedEvents > 0,
              maximumPendingPromises > 0, maximumCallbacks > 0,
              maximumObjectHandles > 0, maximumStorageBytes >= 0
        else { throw HanlinContractError.invalidSchema(reason: "invalid Scripting execution policy") }
        self.schemaVersion = schemaVersion
        self.id = id
        self.context = context
        self.memoryBytes = memoryBytes
        self.stackBytes = stackBytes
        self.deadlineMilliseconds = deadlineMilliseconds
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumQueuedEvents = maximumQueuedEvents
        self.maximumPendingPromises = maximumPendingPromises
        self.maximumCallbacks = maximumCallbacks
        self.maximumObjectHandles = maximumObjectHandles
        self.maximumStorageBytes = maximumStorageBytes
    }

    public static func standard(for context: HanlinExecutionContext) throws -> Self {
        let values: (String, Int, Int, UInt64, Int, Int, Int, Int, Int, Int64) = switch context {
        case .mainApplication: ("foreground-app-v1", 32 << 20, 512 << 10, 10_000, 2 << 20, 256, 128, 128, 256, 16 << 20)
        case .widget: ("widget-v1", 8 << 20, 256 << 10, 1_000, 256 << 10, 32, 16, 16, 32, 1 << 20)
        case .appIntent: ("app-intent-v1", 8 << 20, 256 << 10, 5_000, 256 << 10, 32, 16, 16, 32, 1 << 20)
        case .liveActivity: ("live-activity-v1", 8 << 20, 256 << 10, 1_000, 256 << 10, 32, 16, 16, 32, 1 << 20)
        case .backgroundTask: ("background-v1", 16 << 20, 384 << 10, 15_000, 512 << 10, 64, 32, 32, 64, 4 << 20)
        case .controlWidget, .notificationUI, .keyboard, .translationUI:
            ("extension-v1", 8 << 20, 256 << 10, 2_000, 256 << 10, 32, 16, 16, 32, 1 << 20)
        }
        return try Self(
            id: values.0,
            context: context,
            memoryBytes: values.1,
            stackBytes: values.2,
            deadlineMilliseconds: values.3,
            maximumOutputBytes: values.4,
            maximumQueuedEvents: values.5,
            maximumPendingPromises: values.6,
            maximumCallbacks: values.7,
            maximumObjectHandles: values.8,
            maximumStorageBytes: values.9
        )
    }
}

public enum HanlinScriptAsyncPayload: Codable, Hashable, Sendable {
    case promiseResolved(id: HanlinPromiseID, value: HanlinValue)
    case promiseRejected(id: HanlinPromiseID, error: HanlinPlatformError)
    case callbackRegistered(id: HanlinCallbackID)
    case callbackInvoked(id: HanlinCallbackID, arguments: [HanlinValue])
    case callbackReleased(id: HanlinCallbackID)
    case subscribed(id: HanlinSubscriptionID, topic: String)
    case unsubscribed(id: HanlinSubscriptionID)
    case streamChunk(id: HanlinStreamID, sequence: UInt64, value: HanlinValue)
    case streamCompleted(id: HanlinStreamID, error: HanlinPlatformError?)
    case cancelled(id: HanlinCancellationID)
}

public struct HanlinScriptSessionDescriptor: Codable, Hashable, Sendable {
    public let sessionID: HanlinSessionID
    public let installedPackageID: HanlinInstalledPackageID
    public let entrypointID: String
    public let context: HanlinExecutionContext
    public let policy: HanlinScriptExecutionPolicy

    public init(
        sessionID: HanlinSessionID,
        installedPackageID: HanlinInstalledPackageID,
        entrypointID: String,
        context: HanlinExecutionContext,
        policy: HanlinScriptExecutionPolicy
    ) {
        self.sessionID = sessionID
        self.installedPackageID = installedPackageID
        self.entrypointID = entrypointID
        self.context = context
        self.policy = policy
    }
}
