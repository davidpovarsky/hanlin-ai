// SPDX-License-Identifier: Apache-2.0
/// Noncopyable so a nested helper cannot accidentally fork an invocation's budget.
private final class JSONMeterHealth {
    var failure: (any Error)?
    var observed = Array(repeating: UInt64(0), count: JSONResourceMetric.allCases.count)
}
package struct JSONWorkMeter: ~Copyable {
    /// Keeps the original health alive while a public inout callback borrows an
    /// accumulator. Replacing that accumulator cannot substitute a fresh ledger.
    package struct Continuation {
        private let health: JSONMeterHealth
        fileprivate init(health: JSONMeterHealth) { self.health = health }
        package func check(_ meter: borrowing JSONWorkMeter) throws {
            if let failure = health.failure { throw failure }
            guard health === meter.health else { throw JSONFailure(.configuration, code: .invalidOperation) }
            try meter.checkpoint()
        }
    }
    package var continuation: Continuation { Continuation(health: health) }
    package private(set) var limits: JSONLimits
    private let health = JSONMeterHealth()
    private let trackAcceptedCapacities: Bool
    package private(set) var domain: JSONOperationDomain
    private var counters: [UInt64]
    private var retired: [UInt64]
    private var peak: UInt64 = 0
    private var sinceCancellationCheck: UInt64 = 0
    private var compilingEvaluation = false
    /// Invocation-local qualification observer. Nil in ordinary operations; it
    /// lets native tests rendezvous at an actual owned checkpoint without clocks.
    /// Observer execution itself is trusted test code, outside owned work quotas.
    package var checkpointObserver: (@Sendable (UInt64) -> Void)?
    /// Switches a composed invocation's accounting domain without replacing its ledger.
    /// Work already consumed and terminal health remain unchanged.
    package mutating func operationDomain(_ domain: JSONOperationDomain) throws {
        try checkpoint()
        self.domain = domain
    }
    package mutating func schemaEvaluationPhase(_ active: Bool) { compilingEvaluation = active }
    package init(limits: JSONLimits, domain: JSONOperationDomain, trackAcceptedCapacities: Bool = false) throws {
        try Task.checkCancellation()
        try limits.validate()
        self.limits = limits; self.domain = domain
        self.trackAcceptedCapacities = trackAcceptedCapacities || domain == .coding
        counters = Array(repeating: 0, count: JSONResourceMetric.allCases.count)
        retired = Array(repeating: 0, count: JSONResourceMetric.allCases.count)
    }
    /// Latch an owned subsystem failure before cleaning up its scratch.
    package func recordFailure(_ error: any Error) {
        if health.failure == nil { health.failure = error }
    }
    package func checkpoint() throws {
        if let failure = health.failure { throw failure }
        do {
            checkpointObserver?(used(.workUnits))
            try Task.checkCancellation()
        } catch { health.failure = error; throw error }
    }
    package func used(_ metric: JSONResourceMetric) -> UInt64 { counters[metric.index] }
    package func require(_ metric: JSONResourceMetric, _ attempted: UInt64) throws {
        if let failure = health.failure { throw failure }
        guard attempted <= limits[metric] else {
            let failure = violation(metric, attempted); health.failure = failure; throw failure
        }
        // Fixed-policy operations never tighten after admission. Coding and read
        // scopes retain the capacity history needed by restrict. Cumulative work
        // already lives in counters; live ownership must use current, not peak.
        if trackAcceptedCapacities {
            switch metric {
            case .workUnits, .numericWorkUnits, .compileWorkUnits, .evaluationWorkUnits,
                 .patchWorkUnits, .totalWorkUnits, .regexCompileWorkUnits,
                 .regexSearchWorkUnits, .aggregateRegexWorkUnits, .retainedBytes,
                 .regexRetainedBytes, .annotationBytes, .compiledPlanBytes: break
            default: health.observed[metric.index] = max(health.observed[metric.index], attempted)
            }
        }
    }
    private func violation(_ metric: JSONResourceMetric, _ attempted: UInt64?, overflow: Bool = false) -> JSONFailure {
        let failure = JSONFailure(.resource, code: overflow ? .counterOverflow : .limitExceeded,
                    resource: .init(domain: domain, metric: metric, limit: limits[metric],
                                    attemptedUsage: attempted, overflow: overflow))
        if health.failure == nil { health.failure = failure }
        return failure
    }
    package func adding(_ metric: JSONResourceMetric, _ current: UInt64, _ amount: UInt64) throws -> UInt64 {
        let (next, overflow) = current.addingReportingOverflow(amount)
        guard !overflow else {
            let failure = violation(metric, nil, overflow: true); health.failure = failure; throw failure
        }
        try require(metric, next)
        return next
    }
    package mutating func charge(_ metric: JSONResourceMetric, _ amount: UInt64 = 1) throws {
        let next = try adding(metric, used(metric), amount)
        let (_, reportOverflow) = retired[metric.index].addingReportingOverflow(next)
        guard !reportOverflow else { throw violation(metric, nil, overflow: true) }
        if metric == .nodes && domain == .schemaCompilation {
            let schemaNext = try adding(.schemaNodes, used(.schemaNodes), amount)
            let (_, overflow) = retired[JSONResourceMetric.schemaNodes.index].addingReportingOverflow(schemaNext)
            guard !overflow else { throw violation(.schemaNodes, nil, overflow: true) }
            counters[JSONResourceMetric.schemaNodes.index] = schemaNext
        }
        counters[metric.index] = next
        if metric == .retainedBytes { peak = max(peak, next) }
    }
    /// Split owned execution into blocks no larger than cancellationQuantum.
    /// Subsystem work is inside both the core and the operation-domain work ceiling.
    package mutating func work(_ amount: UInt64 = 1, subsystem: JSONResourceMetric? = nil) throws {
        let total = try adding(.workUnits, used(.workUnits), amount)
        let domainMetric: JSONResourceMetric?
        switch domain {
        case .schemaCompilation: domainMetric = .compileWorkUnits
        case .schemaEvaluation: domainMetric = .evaluationWorkUnits
        case .patch: domainMetric = .patchWorkUnits
        case .streaming: domainMetric = .totalWorkUnits
        default: domainMetric = nil
        }
        let domainNext = try domainMetric.map { try adding($0, used($0), amount) }
        let subsystemNext = try subsystem.map { try adding($0, used($0), amount) }
        let stagedEvaluation = try compilingEvaluation && domain == .schemaCompilation ? adding(.evaluationWorkUnits, used(.evaluationWorkUnits), amount) : nil
        // Report totals include retired record/search work. Admit their sums
        // before committing any counter, just as charge() does for capacities.
        try requireReportSum(.workUnits, total)
        if let metric = domainMetric, let next = domainNext { try requireReportSum(metric, next) }
        if let metric = subsystem, let next = subsystemNext { try requireReportSum(metric, next) }
        if let next = stagedEvaluation { try requireReportSum(.evaluationWorkUnits, next) }
        if amount >= limits[.cancellationQuantum] || sinceCancellationCheck >= limits[.cancellationQuantum] - amount {
            try checkpoint(); sinceCancellationCheck = 0
        } else { sinceCancellationCheck += amount }
        counters[JSONResourceMetric.workUnits.index] = total
        if let metric = domainMetric, let next = domainNext { counters[metric.index] = next }
        if let metric = subsystem, let next = subsystemNext { counters[metric.index] = next }
        if let next = stagedEvaluation { counters[JSONResourceMetric.evaluationWorkUnits.index] = next }
    }
    private func requireReportSum(_ metric: JSONResourceMetric, _ next: UInt64) throws {
        let (_, overflow) = retired[metric.index].addingReportingOverflow(next)
        guard !overflow else { throw violation(metric, nil, overflow: true) }
    }
    package mutating func retain(_ bytes: UInt64) throws {
        try checkpoint()
        let retained = try adding(.retainedBytes,used(.retainedBytes),bytes)
        let plan = try domain == .schemaCompilation ? adding(.compiledPlanBytes,used(.compiledPlanBytes),bytes) : nil
        // Admit both ceilings atomically before any compiler-owned allocation, including scratch.
        if let plan { counters[JSONResourceMetric.compiledPlanBytes.index] = plan }
        counters[JSONResourceMetric.retainedBytes.index] = retained; peak = max(peak,retained)
    }
    /// Tightening keeps the same ledger. Earlier accepted capacities and consumed
    /// work must fit the new ceiling; failures stay terminal even if caught.
    package mutating func restrict(to requested: JSONLimits) throws {
        try checkpoint()
        guard trackAcceptedCapacities else { throw JSONFailure(.configuration, code: .invalidOperation) }
        let restricted = try limits.intersection(requested)
        limits = restricted
        for metric in JSONResourceMetric.allCases where metric != .cancellationQuantum {
            let live = metric == .retainedBytes || metric == .regexRetainedBytes || metric == .annotationBytes || metric == .compiledPlanBytes
            try require(metric, live ? used(metric) : max(used(metric), health.observed[metric.index]))
        }
        sinceCancellationCheck = 0
    }
    /// Bootstrap configuration preserves all admission history and the same terminal ledger.
    /// Unlike a public scope restriction, this permits explicit finite policy overrides.
    package mutating func configure(_ requested: JSONLimits) throws {
        try checkpoint(); try requested.validate()
        guard trackAcceptedCapacities else { throw JSONFailure(.configuration, code: .invalidOperation) }
        limits = requested
        for metric in JSONResourceMetric.allCases where metric != .cancellationQuantum {
            try require(metric, max(used(metric), health.observed[metric.index]))
        }
        sinceCancellationCheck = 0
    }
    /// Only live ownership is refunded; work and lifetime admission remain monotonic.
    package mutating func release(_ bytes: UInt64) throws {
        guard bytes <= used(.retainedBytes) else { throw JSONFailure(.configuration, code: .invalidLimits) }
        if domain == .schemaCompilation {
            guard bytes <= used(.compiledPlanBytes) else { throw JSONFailure(.configuration,code: .invalidLimits) }
            counters[JSONResourceMetric.compiledPlanBytes.index] -= bytes
        }
        counters[JSONResourceMetric.retainedBytes.index] -= bytes
    }
    /// Release a completed record's ownership and reset per-record ceilings only.
    /// The caller supplies live chunk/outer-frame ownership still held by the iterator.
    package mutating func resetRecord(liveBytes: UInt64) throws {
        try checkpoint(); try require(.retainedBytes, liveBytes)
        let lifetime: [JSONResourceMetric] = [.totalInputBytes, .totalRecords, .totalWorkUnits, .totalScannedNodes]
        for metric in JSONResourceMetric.allCases where !lifetime.contains(metric) { try retire(metric) }
        counters[JSONResourceMetric.retainedBytes.index] = liveBytes
    }
    /// Patch checks each staged value independently; charged work remains cumulative.
    private mutating func retire(_ metric: JSONResourceMetric) throws {
        if metric != .retainedBytes && metric != .regexRetainedBytes {
            let (sum, overflow) = retired[metric.index].addingReportingOverflow(counters[metric.index])
            guard !overflow else { throw violation(metric, nil, overflow: true) }
            retired[metric.index] = sum
        }
        counters[metric.index] = 0
    }
    package mutating func resetValueBounds() throws {
        for metric: JSONResourceMetric in [.nodes, .aggregateTextBytes, .outputBytes, .inputBytes] { try retire(metric) }
    }
    package mutating func beginRegexSearch() throws { try retire(.regexSearchWorkUnits) }
    package mutating func releaseRegexState(_ bytes: UInt64) throws {
        guard bytes <= used(.regexRetainedBytes) else { throw JSONFailure(.configuration, code: .invalidLimits) }
        counters[JSONResourceMetric.regexRetainedBytes.index] -= bytes
    }
    package mutating func releaseAnnotationState(_ bytes: UInt64) throws {
        guard bytes <= used(.annotationBytes) else { throw JSONFailure(.configuration, code: .invalidLimits) }
        counters[JSONResourceMetric.annotationBytes.index] -= bytes
    }
    /// Input is a per-document capacity. Retire its charged count into the same
    /// cumulative report; never reset work, retention, accepted history or health.
    package mutating func beginCompositionDocument() throws {
        try checkpoint()
        try retire(.inputBytes)
    }
    /// Composition-only completion owns a separate 49-slot report through handoff.
    /// Existing report entry points retain their original accounting semantics.
    package mutating func compositionStatistics() throws -> JSONOperationStatistics {
        // Version 1 composition receipt: 32 logical header bytes + 49 UInt64 slots.
        try retain(424)
        var report: [UInt64] = []
        report.reserveCapacity(JSONResourceMetric.allCases.count)
        for metric in JSONResourceMetric.allCases {
            try work()
            let (total, overflow) = counters[metric.index].addingReportingOverflow(retired[metric.index])
            guard !overflow else { throw violation(metric, nil, overflow: true) }
            report.append(total)
        }
        // The aggregate-work slot may precede the last copied slot. Charge and
        // publish the final count only after every copied counter is accounted.
        try work()
        let (work, overflow) = counters[JSONResourceMetric.workUnits.index]
            .addingReportingOverflow(retired[JSONResourceMetric.workUnits.index])
        guard !overflow else { throw violation(.workUnits, nil, overflow: true) }
        report[JSONResourceMetric.workUnits.index] = work
        try checkpoint()
        return .init(domain: domain, counters: report, peak: peak)
    }
    package func statistics() -> JSONOperationStatistics {
        var report = counters
        for metric in JSONResourceMetric.allCases { report[metric.index] += retired[metric.index] }
        return .init(domain: domain, counters: report, peak: peak)
    }
}
