// SPDX-License-Identifier: Apache-2.0
/// Stable identifiers for 49 finite resource capacities and work quotas.
///
/// Units and ownership are documented in the resource contract. A capacity check
/// does not necessarily add a cumulative statistic.
public enum JSONResourceMetric: String, CaseIterable, Sendable, Codable {
    /// Inclusive limit in bytes. Before each admitted byte; includes whitespace and source retention.
    case inputBytes
    /// Inclusive limit in open containers. Before stack push; scalar root depth 0, root container depth 1.
    case maxDepth
    /// Inclusive limit in values. Before each value; keys are charged separately.
    case nodes
    /// Inclusive limit in members per object. Before member insertion; total members also charge nodes/work.
    case objectMembers
    /// Inclusive limit in items per array. Before item insertion.
    case arrayItems
    /// Inclusive limit in decoded UTF-8 bytes per string. Before scalar append; excludes object keys.
    case stringBytes
    /// Inclusive limit in decoded UTF-8 bytes. Sum keys and string values, including retained number lexemes separately in retainedBytes.
    case aggregateTextBytes
    /// Inclusive limit in decoded UTF-8 bytes per key. Before key scalar append.
    case keyBytes
    /// Inclusive limit in coefficient digits per token. Before digit append, including zeros before normalization.
    case numberDigits
    /// Inclusive limit in ASCII bytes per number. Before token append; includes exponent spelling.
    case numberTokenBytes
    /// Inclusive limit in absolute mathematical exponent. Checked magnitude while parsing and after normalization; no dense zero expansion.
    case absoluteExponent
    /// Inclusive limit in logical live bytes. Before allocations/reservations in owned state; accounting weights are versioned.
    case retainedBytes
    /// Inclusive limit in primitive operations. Charge inner loops, traversals, comparisons and copying.
    case workUnits
    /// Inclusive limit in decimal limb operations. Nested within total work, no reset in helpers.
    case numericWorkUnits
    /// Inclusive limit in emitted UTF-8 bytes. Before append or sink handoff; writer also applies value/depth/text limits.
    case outputBytes
    /// Inclusive limit in entries. Opt-in only; charge entry and retained source bytes.
    case sourceMapEntries
    /// Inclusive limit in records. Before append; complete output throws on limit rather than silently truncating.
    case issues
    /// Inclusive limit in UTF-8 bytes. Before message/path/preview growth; no raw instance retained.
    case diagnosticBytes
    /// Inclusive limit in charged work units. At entry, before allocation/suspension, and at most this many charged units between checks.
    case cancellationQuantum
    /// Inclusive limit in documents including root.
    case schemaDocuments
    /// Inclusive limit in total admitted resource bytes.
    case schemaBytes
    /// Inclusive limit in nodes across resources.
    case schemaNodes
    /// Inclusive limit in edges.
    case referenceEdges
    /// Inclusive limit in primitive operations.
    case compileWorkUnits
    /// Inclusive limit in logical retained bytes.
    case compiledPlanBytes
    /// Inclusive limit in primitive operations.
    case evaluationWorkUnits
    /// Inclusive limit in active frames including reference/dynamic scopes.
    case evaluationFrames
    /// Inclusive limit in internal evaluated-location and output entries.
    case annotationEntries
    /// Inclusive limit in logical retained bytes.
    case annotationBytes
    /// Inclusive limit in UTF-8 bytes per pattern.
    case regexPatternBytes
    /// Inclusive limit in UTF-8 bytes.
    case aggregateRegexPatternBytes
    /// Inclusive limit in instructions across plan.
    case regexProgramInstructions
    /// Inclusive limit in primitive operations.
    case regexCompileWorkUnits
    /// Inclusive limit in primitive operations per search.
    case regexSearchWorkUnits
    /// Inclusive limit in primitive operations per evaluation.
    case aggregateRegexWorkUnits
    /// Inclusive limit in logical live match state bytes.
    case regexRetainedBytes
    /// Inclusive limit in groups per pattern.
    case regexCaptureGroups
    /// Inclusive limit in accepted source bytes per chunk.
    case chunkBytes
    /// Inclusive limit in unconsumed complete events.
    case pendingEvents
    /// Inclusive limit in unconsumed complete records.
    case pendingValues
    /// Inclusive limit in bytes per iterator lifetime.
    case totalInputBytes
    /// Inclusive limit in records per iterator lifetime.
    case totalRecords
    /// Inclusive limit in primitive operations per iterator lifetime.
    case totalWorkUnits
    /// Inclusive limit in operations.
    case operations
    /// Inclusive limit in UTF-8 bytes per encoded Pointer.
    case pointerBytes
    /// Inclusive limit in tokens per Pointer.
    case pointerTokens
    /// Inclusive limit in primitive operations.
    case patchWorkUnits
    /// Cumulative scanned nodes across an enclosing root-array document, including its outer container.
    case totalScannedNodes
    /// Maximum logical scratch bytes retained across a record boundary; the selected scalar reader retains no reuse pool.
    case maxReusableBufferBytes

    /// UInt64 ledgers never become allocation sizes or array indices. All other
    /// metrics retain the addressable-capacity guard, including numeric exponents.
    package var requiresIntCapacity: Bool {
        switch self {
        case .workUnits, .numericWorkUnits, .compileWorkUnits, .evaluationWorkUnits,
             .regexCompileWorkUnits, .regexSearchWorkUnits, .aggregateRegexWorkUnits,
             .patchWorkUnits, .totalWorkUnits, .totalInputBytes, .totalRecords,
             .totalScannedNodes: false
        default: true
        }
    }

    package var index: Int {
        switch self {
        case .inputBytes: 0
        case .maxDepth: 1
        case .nodes: 2
        case .objectMembers: 3
        case .arrayItems: 4
        case .stringBytes: 5
        case .aggregateTextBytes: 6
        case .keyBytes: 7
        case .numberDigits: 8
        case .numberTokenBytes: 9
        case .absoluteExponent: 10
        case .retainedBytes: 11
        case .workUnits: 12
        case .numericWorkUnits: 13
        case .outputBytes: 14
        case .sourceMapEntries: 15
        case .issues: 16
        case .diagnosticBytes: 17
        case .cancellationQuantum: 18
        case .schemaDocuments: 19
        case .schemaBytes: 20
        case .schemaNodes: 21
        case .referenceEdges: 22
        case .compileWorkUnits: 23
        case .compiledPlanBytes: 24
        case .evaluationWorkUnits: 25
        case .evaluationFrames: 26
        case .annotationEntries: 27
        case .annotationBytes: 28
        case .regexPatternBytes: 29
        case .aggregateRegexPatternBytes: 30
        case .regexProgramInstructions: 31
        case .regexCompileWorkUnits: 32
        case .regexSearchWorkUnits: 33
        case .aggregateRegexWorkUnits: 34
        case .regexRetainedBytes: 35
        case .regexCaptureGroups: 36
        case .chunkBytes: 37
        case .pendingEvents: 38
        case .pendingValues: 39
        case .totalInputBytes: 40
        case .totalRecords: 41
        case .totalWorkUnits: 42
        case .operations: 43
        case .pointerBytes: 44
        case .pointerTokens: 45
        case .patchWorkUnits: 46
        case .totalScannedNodes: 47
        case .maxReusableBufferBytes: 48
        }
    }
}

/// Named finite policy profiles; none represents an unlimited mode.
public enum JSONResourceProfile: Sendable {
    /// The smaller finite profile for constrained input.
    case conservative
    /// The default finite profile for general use.
    case balanced
    /// The larger finite profile for offline work; it remains bounded.
    case offline
}

/// Finite inclusive capacities and cumulative work quotas.
///
/// Balanced is the default. These initial policy values are not hard RSS or
/// throughput guarantees. Validate configurations at operation entry. Composed
/// owned helpers share a meter; separate public calls need caller composition.
public struct JSONLimits: Sendable, Equatable {
    private var maxima: [UInt64]

    /// Loads the finite maxima for the selected policy; balanced is the default.
    ///
    /// - Parameters:
    ///   - profile: The finite resource profile to load.
    public init(profile: JSONResourceProfile = .balanced) {
        switch profile {
        case .conservative: maxima = [4194304, 64, 100000, 20000, 100000, 1048576, 4194304, 16384, 1024, 2048, 100000, 16777216, 8000000, 250000, 4194304, 100000, 32, 65536, 1024, 16, 4194304, 20000, 20000, 4000000, 8388608, 2000000, 256, 20000, 2097152, 4096, 65536, 20000, 250000, 100000, 250000, 2097152, 128, 65536, 1, 1, 268435456, 100000, 512000000, 128, 4096, 64, 2000000, 2000000, 524288]
        case .balanced: maxima = [33554432, 128, 1000000, 100000, 1000000, 8388608, 16777216, 65536, 4096, 8192, 1000000, 67108864, 64000000, 1000000, 33554432, 1000000, 128, 262144, 1024, 128, 33554432, 100000, 200000, 32000000, 33554432, 16000000, 1024, 100000, 8388608, 16384, 262144, 100000, 2000000, 500000, 2000000, 8388608, 512, 262144, 1, 1, 1073741824, 1000000, 2147483648, 1024, 16384, 128, 16000000, 16000000, 2097152]
        case .offline: maxima = [268435456, 256, 4000000, 500000, 4000000, 67108864, 134217728, 262144, 16384, 32768, 10000000, 536870912, 512000000, 8000000, 268435456, 4000000, 512, 1048576, 1024, 512, 268435456, 1000000, 2000000, 256000000, 268435456, 128000000, 4096, 1000000, 67108864, 65536, 2097152, 1000000, 16000000, 4000000, 16000000, 67108864, 2048, 1048576, 1, 1, 68719476736, 16000000, 137438953472, 10000, 65536, 256, 128000000, 128000000, 8388608]
        }
    }
    /// The smaller finite profile for constrained input.
    public static let conservative = Self(profile: .conservative)
    /// The default finite profile for general use.
    public static let balanced = Self(profile: .balanced)
    /// The larger finite profile for offline work; it remains bounded.
    public static let offline = Self(profile: .offline)

    /// Reads or changes the inclusive ceiling for a metric.
    ///
    /// Call validate() or enter an operation to check supported configurations. Zero
    /// forbids quota usage; cancellation and pending capacities have additional rules.
    ///
    /// - Parameters:
    ///   - metric: The stable resource metric to read or configure.
    public subscript(metric: JSONResourceMetric) -> UInt64 {
        get { maxima[metric.index] }
        set { maxima[metric.index] = newValue }
    }

    /// Checks supported finite capacities and cancellation configuration.
    ///
    /// Allocation/index capacities must be below Int.max. Cumulative UInt64 quotas
    /// must be below UInt64.max; cancellation quantum must be 1...1024
    /// and pending event/value capacities must be at most one. Zero forbids quota usage.
    /// - Throws: `JSONFailure` with invalidLimits for unsupported configurations.
    public func validate() throws {
        for metric in JSONResourceMetric.allCases {
            let maximum = self[metric]
            // Ordinary capacities take the original single-read fast path.
            // Only wider UInt64 quotas need classification; UInt64.max still fails.
            guard maximum < UInt64(Int.max) ||
                  (!metric.requiresIntCapacity && maximum < UInt64.max) else {
                throw JSONFailure(.configuration, code: .invalidLimits)
            }
        }
        guard (1...1024).contains(self[.cancellationQuantum]),
              self[.pendingEvents] <= 1, self[.pendingValues] <= 1 else {
            throw JSONFailure(.configuration, code: .invalidLimits)
        }
    }
}

/// Versioned logical retention weights, independent of allocator sizes and process RSS.
public enum JSONLogicalWeights {
    /// The logical weight version, currently 1.
    public static let version: UInt32 = 1
    /// Logical bytes reserved per value node.
    public static let node: UInt64 = 32
    /// Logical bytes reserved per object member slot.
    public static let member: UInt64 = 24
    /// Logical bytes reserved per array element slot.
    public static let arraySlot: UInt64 = 16
    /// Logical bytes reserved per traversal or evaluation frame.
    public static let frame: UInt64 = 16
    /// Logical bytes reserved per source-map entry.
    public static let sourceMapEntry: UInt64 = 32
    /// Logical bytes reserved per index slot.
    public static let indexSlot: UInt64 = 32
    /// Logical bytes reserved per annotation entry.
    public static let annotationEntry: UInt64 = 32
    /// Logical bytes reserved per regex instruction.
    public static let regexInstruction: UInt64 = 16
    /// Logical bytes reserved per regex state record.
    public static let regexStateRecord: UInt64 = 32
}

extension JSONLimits {
    package func intersection(_ other: Self) throws -> Self {
        try validate(); try other.validate()
        var result = self
        for metric in JSONResourceMetric.allCases { result[metric] = min(self[metric], other[metric]) }
        return result
    }
}
