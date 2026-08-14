import Foundation

public struct HanlinScriptExecutionLimits: Codable, Hashable, Sendable {
    public let timeoutMilliseconds: Int64
    public let maximumOutputBytes: Int
    public let maximumMemoryBytes: Int64?

    public init(
        timeoutMilliseconds: Int64,
        maximumOutputBytes: Int,
        maximumMemoryBytes: Int64? = nil
    ) throws {
        guard timeoutMilliseconds > 0,
              maximumOutputBytes > 0,
              maximumOutputBytes <= 8 * 1_048_576,
              maximumMemoryBytes.map({ $0 > 0 }) ?? true
        else {
            throw HanlinContractError.invalidSchema(reason: "invalid script execution limits")
        }
        self.timeoutMilliseconds = timeoutMilliseconds
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumMemoryBytes = maximumMemoryBytes
    }
}

public struct HanlinScriptExecutionRequest: Codable, Hashable, Sendable {
    public let id: HanlinScriptExecutionID
    public let runtimeSessionID: HanlinRuntimeSessionID
    public let installedPackageID: HanlinInstalledPackageID
    public let appID: HanlinAppID?
    public let logicalEntryPoint: String
    public let compilerLane: String
    public let compilerVersion: String
    public let compilerConfigurationHash: String
    public let parameters: HanlinValue
    public let grantIDs: [HanlinGrantID]
    public let limits: HanlinScriptExecutionLimits

    public init(
        id: HanlinScriptExecutionID,
        runtimeSessionID: HanlinRuntimeSessionID,
        installedPackageID: HanlinInstalledPackageID,
        appID: HanlinAppID? = nil,
        logicalEntryPoint: String,
        compilerLane: String,
        compilerVersion: String,
        compilerConfigurationHash: String,
        parameters: HanlinValue,
        grantIDs: [HanlinGrantID] = [],
        limits: HanlinScriptExecutionLimits
    ) {
        self.id = id
        self.runtimeSessionID = runtimeSessionID
        self.installedPackageID = installedPackageID
        self.appID = appID
        self.logicalEntryPoint = logicalEntryPoint
        self.compilerLane = compilerLane
        self.compilerVersion = compilerVersion
        self.compilerConfigurationHash = compilerConfigurationHash
        self.parameters = parameters
        self.grantIDs = grantIDs
        self.limits = limits
    }
}

public enum HanlinScriptExecutionOutcome: Codable, Hashable, Sendable {
    case completed(HanlinValue?)
    case compileOnly(diagnostics: [String])
    case failed(HanlinPlatformError)
    case cancelled(HanlinCancellationID)
    case timedOut
}

public struct HanlinScriptExecutionResult: Codable, Hashable, Sendable {
    public let executionID: HanlinScriptExecutionID
    public let outcome: HanlinScriptExecutionOutcome
    public let startedAt: Date?
    public let completedAt: Date

    public init(
        executionID: HanlinScriptExecutionID,
        outcome: HanlinScriptExecutionOutcome,
        startedAt: Date? = nil,
        completedAt: Date
    ) {
        self.executionID = executionID
        self.outcome = outcome
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public enum HanlinScriptStreamKind: String, Codable, Hashable, Sendable {
    case standardOutput
    case standardError
    case progress
    case value
    case terminal
}

public struct HanlinScriptStreamEvent: Codable, Hashable, Sendable {
    public let executionID: HanlinScriptExecutionID
    public let sequence: UInt64
    public let timestamp: Date
    public let kind: HanlinScriptStreamKind
    public let payload: HanlinValue

    public init(
        executionID: HanlinScriptExecutionID,
        sequence: UInt64,
        timestamp: Date,
        kind: HanlinScriptStreamKind,
        payload: HanlinValue
    ) {
        self.executionID = executionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.payload = payload
    }
}
