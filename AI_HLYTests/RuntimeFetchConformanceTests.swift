import CryptoKit
import Foundation
import Testing
@testable import AI_Hanlin

private final class RuntimeNetworkFixtureMarker: NSObject {}

@MainActor
@Suite("Actual embedded Fetch transport", .serialized)
struct RuntimeFetchConformanceTests {
    @Test(.timeLimit(.minutes(2)))
    func nativeTLSIntegrityProxyAndStreams() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.node.ensureRunning()
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "native-fetch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let bundle = Bundle(for: RuntimeNetworkFixtureMarker.self)
        let foundFixture = bundle.url(forResource: "RuntimeNetworkFixtures", withExtension: "bundle", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "RuntimeNetworkFixtures", withExtension: "bundle")
        let fixture = try #require(foundFixture, "The shared transport fixture bundle must be present")
        let local = workspace.appending(path: "fixture", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: fixture, to: local)
        let foundArchive = Bundle.main.url(forResource: "RuntimeHostResources", withExtension: "zip")
        let archive = try #require(foundArchive)
        let digest = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let host = RuntimeFileLayout.default.nodeRuntime.appending(path: "host-\(digest)", directoryHint: .isDirectory)
        let source = """
        import {createRequire} from 'node:module'; import {readFileSync} from 'node:fs';
        import {runFetchConformance} from \(json(local.appending(path: "probe.mjs").absoluteString));
        const {Agent,ProxyAgent}=createRequire(\(json(host.appending(path: "package.json").path)))('undici');
        const tlsFixture=JSON.parse(readFileSync(\(json(local.appending(path: "tls-fixture.json").path)),'utf8'));
        const report=await runFetchConformance({Agent,ProxyAgent,tlsFixture});
        console.log(JSON.stringify(report));export default report;
        """
        let result = try await core.node.executeJavaScript(RuntimeExecutionRequest(source: source, workspace: workspace), moduleKind: "esm")
        #expect(result.exitCode == 0, "\(result.stderr)")
        let report = try JSONDecoder().decode(Report.self, from: Data(result.stdout.utf8))
        #expect(report.passed && report.wasm)
        #expect(report.nodeVersion == NodeRuntimeService.expectedNodeVersion)
        #expect(report.contracts.count == 12)
        #expect(report.tunnels.count == 2)
        #expect(!report.nonce.isEmpty)
    }

    private func json(_ value: String) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    private struct Report: Decodable {
        let passed: Bool
        let wasm: Bool
        let nodeVersion: String
        let nonce: String
        let contracts: [String]
        let tunnels: [String]
    }
}
