import Foundation

enum CanonicalShadowDomain: String, CaseIterable, Codable, Hashable, Sendable {
    case foundationJSON = "foundation.json"
    case nativeApplications = "native.applications"
    case nativeTools = "native.tools"
    case mcp = "mcp"
    case runtimeCore = "runtime.core"
    case crossDomainTools = "cross-domain.tools"
}

enum CanonicalShadowStatus: String, Codable, Hashable, Sendable {
    case passed
    case warning
    case mismatch
    case skipped
}

enum CanonicalShadowSeverity: String, Codable, Hashable, Sendable {
    case information
    case warning
    case mismatch
}

struct CanonicalShadowFinding: Codable, Hashable, Sendable {
    let severity: CanonicalShadowSeverity
    let code: String
    let path: String
    let message: String
}

struct CanonicalShadowItem: Codable, Hashable, Sendable {
    let identity: String
    let alias: String?
    let providerIdentity: String?
    let descriptorRevision: UInt64?
    let schemaIsValid: Bool

    init(
        identity: String,
        alias: String? = nil,
        providerIdentity: String? = nil,
        descriptorRevision: UInt64? = nil,
        schemaIsValid: Bool = true
    ) {
        self.identity = identity
        self.alias = alias
        self.providerIdentity = providerIdentity
        self.descriptorRevision = descriptorRevision
        self.schemaIsValid = schemaIsValid
    }
}

struct CanonicalShadowDomainReport: Codable, Hashable, Sendable {
    let domain: CanonicalShadowDomain
    let status: CanonicalShadowStatus
    let sourceCount: Int?
    let projectedCount: Int?
    let findings: [CanonicalShadowFinding]

    init(
        domain: CanonicalShadowDomain,
        status: CanonicalShadowStatus? = nil,
        sourceCount: Int? = nil,
        projectedCount: Int? = nil,
        findings: [CanonicalShadowFinding] = []
    ) {
        let orderedFindings = findings.sorted(by: CanonicalShadowOrdering.findings)
        self.domain = domain
        self.status = status ?? Self.status(for: orderedFindings)
        self.sourceCount = sourceCount
        self.projectedCount = projectedCount
        self.findings = orderedFindings
    }

    static func skipped(_ domain: CanonicalShadowDomain, code: String) -> Self {
        .init(
            domain: domain,
            status: .skipped,
            findings: [
                .init(
                    severity: .information,
                    code: code,
                    path: domain.rawValue,
                    message: "Source state was not observable at this diagnostic point."
                )
            ]
        )
    }

    private static func status(
        for findings: [CanonicalShadowFinding]
    ) -> CanonicalShadowStatus {
        if findings.contains(where: { $0.severity == .mismatch }) {
            return .mismatch
        }
        if findings.contains(where: { $0.severity == .warning }) {
            return .warning
        }
        return .passed
    }
}

struct CanonicalShadowSummary: Codable, Hashable, Sendable {
    let passedCount: Int
    let warningCount: Int
    let mismatchCount: Int
    let skippedCount: Int

    init(domains: [CanonicalShadowDomainReport]) {
        passedCount = domains.filter { $0.status == .passed }.count
        warningCount = domains.filter { $0.status == .warning }.count
        mismatchCount = domains.filter { $0.status == .mismatch }.count
        skippedCount = domains.filter { $0.status == .skipped }.count
    }
}

struct CanonicalShadowReport: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let domains: [CanonicalShadowDomainReport]
    let summary: CanonicalShadowSummary

    init(domains: [CanonicalShadowDomainReport]) {
        let reportsByDomain = Dictionary(uniqueKeysWithValues: domains.map { ($0.domain, $0) })
        let ordered = CanonicalShadowDomain.allCases.map { domain in
            reportsByDomain[domain] ?? .skipped(
                domain,
                code: "\(domain.rawValue).notObservable"
            )
        }
        schemaVersion = 1
        self.domains = ordered
        summary = CanonicalShadowSummary(domains: ordered)
    }

    var summaryLine: String {
        let observed = domains
            .filter { $0.status != .skipped }
            .map(\.domain.rawValue)
            .joined(separator: ",")
        let skipped = domains
            .filter { $0.status == .skipped }
            .map(\.domain.rawValue)
            .joined(separator: ",")
        let mismatchCodes = domains
            .flatMap(\.findings)
            .filter { $0.severity == .mismatch }
            .map(\.code)
            .sorted()
            .joined(separator: ",")
        return "schema=\(schemaVersion) observed=\(observed) skipped=\(skipped) "
            + "passed=\(summary.passedCount) warnings=\(summary.warningCount) "
            + "mismatches=\(summary.mismatchCount) codes=\(mismatchCodes)"
    }
}

enum CanonicalShadowComparison {
    static func compare(
        domain: CanonicalShadowDomain,
        source: [CanonicalShadowItem],
        projected: [CanonicalShadowItem],
        repeatedProjection: [CanonicalShadowItem],
        additionalFindings: [CanonicalShadowFinding] = []
    ) -> CanonicalShadowDomainReport {
        let sourceItems = source.sorted(by: CanonicalShadowOrdering.items)
        let projectedItems = projected.sorted(by: CanonicalShadowOrdering.items)
        let repeatedItems = repeatedProjection.sorted(by: CanonicalShadowOrdering.items)
        var findings = additionalFindings

        if sourceItems.count != projectedItems.count {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).countMismatch",
                path: domain.rawValue,
                message: "Source and canonical projection counts differ."
            ))
        }

        let sourceIdentities = sourceItems.map(\.identity)
        let projectedIdentities = projectedItems.map(\.identity)
        if sourceIdentities != projectedIdentities {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).identityMismatch",
                path: domain.rawValue,
                message: "Source and canonical identities differ."
            ))
        }

        let sourceAliases = sourceItems.map { ($0.identity, $0.alias) }
        let projectedAliases = projectedItems.map { ($0.identity, $0.alias) }
        if !aliasesEqual(sourceAliases, projectedAliases) {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).aliasMismatch",
                path: domain.rawValue,
                message: "Source and canonical model-facing aliases differ."
            ))
        }

        let sourceProviders = sourceItems.map { ($0.identity, $0.providerIdentity) }
        let projectedProviders = projectedItems.map { ($0.identity, $0.providerIdentity) }
        if !providersEqual(sourceProviders, projectedProviders) {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).providerMismatch",
                path: domain.rawValue,
                message: "Source and canonical provider identities differ."
            ))
        }

        for identity in duplicates(projectedIdentities) {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).duplicateIdentity",
                path: "\(domain.rawValue)/\(identity)",
                message: "A canonical identity occurs more than once."
            ))
        }

        for alias in duplicates(projectedItems.compactMap(\.alias)) {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).aliasCollision",
                path: "\(domain.rawValue)/aliases/\(alias)",
                message: "A model-facing alias resolves to more than one projected item."
            ))
        }

        for item in projectedItems where item.descriptorRevision == 0 {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).invalidDescriptorRevision",
                path: "\(domain.rawValue)/\(item.identity)/descriptorRevision",
                message: "The projected descriptor revision is invalid."
            ))
        }

        for item in projectedItems where !item.schemaIsValid {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).invalidSchema",
                path: "\(domain.rawValue)/\(item.identity)/schema",
                message: "The projected canonical schema is invalid."
            ))
        }

        if projectedItems != repeatedItems {
            findings.append(.init(
                severity: .mismatch,
                code: "\(domain.rawValue).identityInstability",
                path: domain.rawValue,
                message: "Repeated projection of the same source state was not stable."
            ))
        }

        return .init(
            domain: domain,
            sourceCount: sourceItems.count,
            projectedCount: projectedItems.count,
            findings: findings
        )
    }

    private static func duplicates(_ values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }

    private static func aliasesEqual(
        _ left: [(String, String?)],
        _ right: [(String, String?)]
    ) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1
        }
    }

    private static func providersEqual(
        _ left: [(String, String?)],
        _ right: [(String, String?)]
    ) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1
        }
    }
}

private enum CanonicalShadowOrdering {
    static func findings(
        _ left: CanonicalShadowFinding,
        _ right: CanonicalShadowFinding
    ) -> Bool {
        (left.code, left.path, left.message) < (right.code, right.path, right.message)
    }

    static func items(_ left: CanonicalShadowItem, _ right: CanonicalShadowItem) -> Bool {
        (
            left.identity,
            left.alias ?? "",
            left.providerIdentity ?? "",
            left.descriptorRevision ?? 0
        ) < (
            right.identity,
            right.alias ?? "",
            right.providerIdentity ?? "",
            right.descriptorRevision ?? 0
        )
    }
}
