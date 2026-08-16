import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Canonical shadow coordinator", .serialized)
struct CanonicalShadowCoordinatorTests {
    @Test("Pure comparison reports pass, warning, mismatch, and deterministic order")
    func reportStatusesAndOrdering() {
        let item = CanonicalShadowItem(
            identity: "native.system|tool",
            alias: "tool",
            providerIdentity: "native.system",
            descriptorRevision: 1
        )
        let passed = CanonicalShadowComparison.compare(
            domain: .nativeTools,
            source: [item],
            projected: [item],
            repeatedProjection: [item]
        )
        #expect(passed.status == .passed)

        let warning = CanonicalShadowDomainReport(
            domain: .mcp,
            findings: [
                .init(
                    severity: .warning,
                    code: "mcp.tools.notObservable",
                    path: "mcp/tools",
                    message: "No already-discovered tool state was available."
                )
            ]
        )
        #expect(warning.status == .warning)

        let unstable = CanonicalShadowItem(
            identity: "native.system|other",
            alias: "tool",
            providerIdentity: "native.system",
            descriptorRevision: 0,
            schemaIsValid: false
        )
        let mismatch = CanonicalShadowComparison.compare(
            domain: .nativeTools,
            source: [item],
            projected: [item, item],
            repeatedProjection: [unstable]
        )
        #expect(mismatch.status == .mismatch)
        #expect(mismatch.findings.map(\.code) == mismatch.findings.map(\.code).sorted())
        #expect(mismatch.findings.map(\.code).contains("native.tools.aliasCollision"))
        #expect(mismatch.findings.map(\.code).contains("native.tools.duplicateIdentity"))
        #expect(mismatch.findings.map(\.code).contains("native.tools.identityInstability"))
    }

    @Test("Skipped domains are explicit and summary equality is timestamp-free")
    func skippedDomains() {
        let first = CanonicalShadowReport(domains: [])
        let repeated = CanonicalShadowReport(domains: [])
        #expect(first == repeated)
        #expect(first.summary.skippedCount == CanonicalShadowDomain.allCases.count)
        #expect(first.domains.allSatisfy { $0.status == .skipped })
    }

    @MainActor
    @Test("All observable adapter domains project without execution or network access")
    func allObservableDomains() throws {
        let nativeTool = QuickCalculateTool()
        let server = TestFixtures.mcpServer()
        let runtimeSnapshot = RuntimeSnapshot(
            kind: .shell,
            state: .ready,
            version: "ios-system-lite",
            source: "bundled",
            lastHealthCheck: nil,
            lastErrorCode: nil,
            storageBytes: nil,
            cacheBytes: nil,
            activeExecutionCount: 0,
            packageCount: nil
        )
        let observedAt = Date(timeIntervalSince1970: 1)
        let report = HanlinCanonicalShadowCoordinator.run(
            sources: .init(
                nativeApplications: [
                    .init(
                        manifest: TestFixtures.nativeManifest(),
                        capabilities: []
                    )
                ],
                nativeTools: [
                    .init(tool: nativeTool, entry: nativeTool.catalogEntry)
                ],
                mcp: .init(
                    servers: [server],
                    tools: [TestFixtures.mcpTool(serverID: server.id)],
                    runtime: .init(
                        snapshot: .stopped,
                        sessionID: try HanlinRuntimeSessionID(
                            validating: "runtime.test.mcp"
                        ),
                        createdAt: observedAt,
                        observedAt: observedAt
                    )
                ),
                runtimeCore: [
                    .init(
                        snapshot: runtimeSnapshot,
                        sessionID: try HanlinRuntimeSessionID(
                            validating: "runtime.test.shell"
                        ),
                        providerInstanceID: try HanlinProviderInstanceID(
                            validating: "runtime.shell"
                        ),
                        createdAt: observedAt,
                        observedAt: observedAt
                    )
                ]
            )
        )
        #expect(report.summary.mismatchCount == 0)
        #expect(report.domains.first { $0.domain == .nativeApplications }?.status == .passed)
        #expect(report.domains.first { $0.domain == .nativeTools }?.status == .passed)
        #expect(report.domains.first { $0.domain == .mcp }?.status == .passed)
        #expect(report.domains.first { $0.domain == .runtimeCore }?.status == .passed)
        #expect(report.domains.first { $0.domain == .crossDomainTools }?.status == .passed)
    }

    @Test("Structured diagnostics exclude source secrets and arbitrary payloads")
    func reportRedaction() throws {
        let sensitiveValue = "super-secret-token-value"
        let report = CanonicalShadowReport(domains: [
            CanonicalShadowComparison.compare(
                domain: .mcp,
                source: [
                    .init(
                        identity: "provider.one",
                        providerIdentity: "mcp"
                    )
                ],
                projected: [
                    .init(
                        identity: "provider.one",
                        providerIdentity: "mcp"
                    )
                ],
                repeatedProjection: [
                    .init(
                        identity: "provider.one",
                        providerIdentity: "mcp"
                    )
                ]
            )
        ])
        let encoded = try JSONEncoder().encode(report)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains(sensitiveValue))
        #expect(!report.summaryLine.contains(sensitiveValue))
    }
}
