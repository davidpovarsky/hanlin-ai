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
        let mcpTool = TestFixtures.mcpTool(serverID: server.id)
        let observedAt = Date(timeIntervalSince1970: 1)
        let nativeSource = HanlinCanonicalShadowCoordinator.NativeToolSource(
            tool: nativeTool,
            entry: nativeTool.catalogEntry
        )
        let nativeAuthoritySource = HanlinCanonicalToolAuthority.NativeSource(
            entry: nativeTool.catalogEntry,
            canonicalSchema: nativeTool.openAIToolSchema(),
            modelSchema: nativeTool.openAIToolSchema()
        )
        let firstAuthority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeAuthoritySource],
            mcpTools: [mcpTool],
            generatedAt: observedAt
        )
        let repeatedAuthority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeAuthoritySource],
            mcpTools: [mcpTool],
            generatedAt: observedAt
        )
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
        let report = HanlinCanonicalShadowCoordinator.run(
            sources: .init(
                nativeApplications: [
                    .init(
                        manifest: TestFixtures.nativeManifest(),
                        capabilities: []
                    )
                ],
                nativeTools: [
                    nativeSource
                ],
                mcp: .init(
                    servers: [server],
                    tools: [mcpTool],
                    runtime: .init(
                        snapshot: .stopped,
                        sessionID: try HanlinRuntimeSessionID(
                            validating: "runtime.test.mcp"
                        ),
                        createdAt: observedAt,
                        observedAt: observedAt
                    )
                ),
                combinedTools: .init(
                    nativeTools: [nativeSource],
                    mcpTools: [mcpTool],
                    authoritativeCatalog: firstAuthority.catalog,
                    repeatedCatalog: repeatedAuthority.catalog,
                    routingTable: firstAuthority.routingTable,
                    repeatedRoutingTable: repeatedAuthority.routingTable,
                    routes: [
                        .init(
                            logicalIdentity: "native.system|quick_calculate",
                            alias: "quick_calculate",
                            backend: .native,
                            backendProviderIdentity: "native.system",
                            targetExists: true
                        ),
                        .init(
                            logicalIdentity: "\(server.id.uuidString.lowercased())|echo",
                            alias: mcpTool.exposedName,
                            backend: .mcp,
                            backendProviderIdentity: server.id.uuidString.lowercased(),
                            targetExists: true
                        )
                    ]
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

    @MainActor
    @Test("Combined tool parity rejects collisions, missing targets, and orphan routes")
    func combinedToolRouteFailures() throws {
        let nativeTool = QuickCalculateTool()
        let nativeSource = HanlinCanonicalShadowCoordinator.NativeToolSource(
            tool: nativeTool,
            entry: nativeTool.catalogEntry
        )
        var mcpTool = TestFixtures.mcpTool()
        mcpTool.exposedName = nativeTool.name
        let descriptorRevision = try HanlinDescriptorRevision(1)
        let nativeDescriptor = try NativeToolCanonicalShadowAdapter.project(
            tool: nativeTool,
            entry: nativeTool.catalogEntry,
            descriptorRevision: descriptorRevision
        ).descriptor
        let mcpDescriptor = try MCPCanonicalShadowAdapter.projectTool(
            mcpTool,
            descriptorRevision: descriptorRevision
        )
        let revision = HanlinCatalogRevision(1)
        let catalog = HanlinToolCatalogSnapshot(
            revision: revision,
            generatedAt: Date(timeIntervalSince1970: 1),
            entries: [
                .init(
                    descriptor: nativeDescriptor,
                    availability: .available,
                    modelAlias: nativeTool.name
                ),
                .init(
                    descriptor: mcpDescriptor,
                    availability: .available,
                    modelAlias: nativeTool.name
                )
            ]
        )
        let routingTable = try HanlinToolRoutingTable(
            revision: revision,
            routes: [
                .init(
                    alias: nativeTool.name,
                    logicalToolID: nativeDescriptor.logicalID,
                    descriptorRevision: descriptorRevision
                ),
                .init(
                    alias: "mcp__test_server__echo",
                    logicalToolID: mcpDescriptor.logicalID,
                    descriptorRevision: descriptorRevision
                )
            ]
        )
        let report = HanlinCanonicalShadowCoordinator.run(
            sources: .init(
                combinedTools: .init(
                    nativeTools: [nativeSource],
                    mcpTools: [mcpTool],
                    authoritativeCatalog: catalog,
                    repeatedCatalog: catalog,
                    routingTable: routingTable,
                    repeatedRoutingTable: routingTable,
                    routes: [
                        .init(
                            logicalIdentity: "native.system|quick_calculate",
                            alias: nativeTool.name,
                            backend: .native,
                            backendProviderIdentity: "native.system",
                            targetExists: true
                        ),
                        .init(
                            logicalIdentity: "\(mcpTool.serverID.uuidString.lowercased())|echo",
                            alias: nativeTool.name,
                            backend: .mcp,
                            backendProviderIdentity: mcpTool.serverID.uuidString.lowercased(),
                            targetExists: false
                        ),
                        .init(
                            logicalIdentity: "native.system|orphan",
                            alias: "orphan",
                            backend: .mcp,
                            backendProviderIdentity: "native.system",
                            targetExists: true
                        )
                    ]
                )
            )
        )
        let combined = report.domains.first { $0.domain == .crossDomainTools }
        let codes = combined?.findings.map(\.code) ?? []
        #expect(combined?.status == .mismatch)
        #expect(codes.contains("cross-domain.tools.aliasCollision"))
        #expect(codes.contains("cross-domain.tools.routeAliasCollision"))
        #expect(codes.contains("cross-domain.tools.missingRouteTarget"))
        #expect(codes.contains("cross-domain.tools.orphanedRoute"))
        #expect(codes.contains("cross-domain.tools.backendProviderMismatch"))
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
