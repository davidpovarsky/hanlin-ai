import Foundation

public struct HanlinLogicalToolID: Codable, Hashable, Sendable {
    public let providerInstanceID: HanlinProviderInstanceID
    public let localToolID: HanlinToolID

    public init(
        providerInstanceID: HanlinProviderInstanceID,
        localToolID: HanlinToolID
    ) {
        self.providerInstanceID = providerInstanceID
        self.localToolID = localToolID
    }
}

public enum HanlinToolAvailability: String, Codable, Hashable, Sendable {
    case available
    case disabled
    case providerUnavailable
    case incompatible
    case invalidDescriptor
}

public struct HanlinToolRoute: Codable, Hashable, Sendable {
    public let alias: String
    public let logicalToolID: HanlinLogicalToolID
    public let descriptorRevision: HanlinDescriptorRevision

    public init(
        alias: String,
        logicalToolID: HanlinLogicalToolID,
        descriptorRevision: HanlinDescriptorRevision
    ) {
        self.alias = alias
        self.logicalToolID = logicalToolID
        self.descriptorRevision = descriptorRevision
    }
}

public struct HanlinToolRoutingTable: Codable, Hashable, Sendable {
    public let revision: HanlinCatalogRevision
    public let routes: [HanlinToolRoute]

    public init(revision: HanlinCatalogRevision, routes: [HanlinToolRoute]) throws {
        var aliases: Set<String> = []
        guard routes.allSatisfy({ aliases.insert($0.alias).inserted }) else {
            throw HanlinContractError.invalidSchema(
                reason: "tool routing aliases must be unique; collisions never overwrite"
            )
        }
        self.revision = revision
        self.routes = routes.sorted { $0.alias < $1.alias }
    }

    public func route(alias: String) -> HanlinToolRoute? {
        routes.first { $0.alias == alias }
    }
}

public struct HanlinToolCatalogEntry: Codable, Hashable, Sendable {
    public let descriptor: HanlinToolDescriptor
    public let availability: HanlinToolAvailability
    public let modelAlias: String?

    public init(
        descriptor: HanlinToolDescriptor,
        availability: HanlinToolAvailability,
        modelAlias: String? = nil
    ) {
        self.descriptor = descriptor
        self.availability = availability
        self.modelAlias = modelAlias
    }
}

public struct HanlinToolCatalogSnapshot: Codable, Hashable, Sendable {
    public let revision: HanlinCatalogRevision
    public let generatedAt: Date
    public let entries: [HanlinToolCatalogEntry]

    public init(
        revision: HanlinCatalogRevision,
        generatedAt: Date,
        entries: [HanlinToolCatalogEntry]
    ) {
        self.revision = revision
        self.generatedAt = generatedAt
        self.entries = entries
    }
}

public struct HanlinToolInvocationLimits: Codable, Hashable, Sendable {
    public let timeoutMilliseconds: Int64
    public let maximumOutputBytes: Int

    public init(
        timeoutMilliseconds: Int64 = 30_000,
        maximumOutputBytes: Int = 1_048_576
    ) throws {
        guard timeoutMilliseconds > 0,
              maximumOutputBytes > 0,
              maximumOutputBytes <= 8 * 1_048_576
        else {
            throw HanlinContractError.invalidSchema(
                reason: "tool invocation limits must be positive and within the host hard cap"
            )
        }
        self.timeoutMilliseconds = timeoutMilliseconds
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public struct HanlinToolInvocationRequest: Codable, Hashable, Sendable {
    public let id: HanlinToolInvocationID
    public let logicalToolID: HanlinLogicalToolID
    public let aliasUsed: String
    public let descriptorRevision: HanlinDescriptorRevision
    public let routingTableRevision: HanlinCatalogRevision
    public let arguments: HanlinJSONValue
    public let origin: HanlinExecutionOrigin
    public let appSessionID: HanlinAppSessionID?
    public let runtimeSessionID: HanlinRuntimeSessionID?
    public let grantIDs: [HanlinGrantID]
    public let idempotencyKey: String?
    public let deadline: Date?
    public let limits: HanlinToolInvocationLimits

    public init(
        id: HanlinToolInvocationID,
        logicalToolID: HanlinLogicalToolID,
        aliasUsed: String,
        descriptorRevision: HanlinDescriptorRevision,
        routingTableRevision: HanlinCatalogRevision,
        arguments: HanlinJSONValue,
        origin: HanlinExecutionOrigin,
        appSessionID: HanlinAppSessionID? = nil,
        runtimeSessionID: HanlinRuntimeSessionID? = nil,
        grantIDs: [HanlinGrantID] = [],
        idempotencyKey: String? = nil,
        deadline: Date? = nil,
        limits: HanlinToolInvocationLimits
    ) {
        self.id = id
        self.logicalToolID = logicalToolID
        self.aliasUsed = aliasUsed
        self.descriptorRevision = descriptorRevision
        self.routingTableRevision = routingTableRevision
        self.arguments = arguments
        self.origin = origin
        self.appSessionID = appSessionID
        self.runtimeSessionID = runtimeSessionID
        self.grantIDs = grantIDs
        self.idempotencyKey = idempotencyKey
        self.deadline = deadline
        self.limits = limits
    }
}

public enum HanlinToolContent: Codable, Hashable, Sendable {
    case text(String)
    case structured(HanlinValue)
    case attachment(handle: String, mediaType: String, byteCount: Int64)
    case resourceLink(uri: String, title: String?)
}

public enum HanlinToolOutcome: Codable, Hashable, Sendable {
    case completed([HanlinToolContent])
    case failed(HanlinPlatformError)
    case denied(HanlinPolicyEvaluationID, String)
    case cancelled(HanlinCancellationID, stage: String)
    case timedOut(deadline: Date?, cleanupCompleted: Bool)
}

public struct HanlinToolInvocationResult: Codable, Hashable, Sendable {
    public let invocationID: HanlinToolInvocationID
    public let logicalToolID: HanlinLogicalToolID
    public let outcome: HanlinToolOutcome
    public let startedAt: Date?
    public let completedAt: Date

    public init(
        invocationID: HanlinToolInvocationID,
        logicalToolID: HanlinLogicalToolID,
        outcome: HanlinToolOutcome,
        startedAt: Date? = nil,
        completedAt: Date
    ) {
        self.invocationID = invocationID
        self.logicalToolID = logicalToolID
        self.outcome = outcome
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct HanlinToolProgressEvent: Codable, Hashable, Sendable {
    public let invocationID: HanlinToolInvocationID
    public let sequence: UInt64
    public let timestamp: Date
    public let fractionCompleted: Double?
    public let message: String?

    public init(
        invocationID: HanlinToolInvocationID,
        sequence: UInt64,
        timestamp: Date,
        fractionCompleted: Double? = nil,
        message: String? = nil
    ) throws {
        if let fractionCompleted,
           (!fractionCompleted.isFinite || !(0 ... 1).contains(fractionCompleted))
        {
            throw HanlinContractError.invalidNumber(fractionCompleted)
        }
        self.invocationID = invocationID
        self.sequence = sequence
        self.timestamp = timestamp
        self.fractionCompleted = fractionCompleted
        self.message = message
    }
}
