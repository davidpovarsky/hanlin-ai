#!/usr/bin/env python3
"""Compile the actual cache with a minimal SwiftData-free original-getter fixture.

This verifies cache behavior without an iOS Simulator. Apple model integration
is covered separately by AgentRunReadCacheTests and the app build.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'AI_HLY/Downstream/ChatPresentation/HanlinAgentRunReadCache.swift'
FIXTURE = r'''
import Foundation
struct AgentRun: Codable, Equatable {
    static let currentSchemaVersion = 4
    var schemaVersion = 4
    var id: UUID
    var modelID: String
}
@MainActor final class ChatMessages {
    let id = UUID()
    var agentRunJSON: String?
    var agentRun: AgentRun? {
        get {
            guard let agentRunJSON, let data = agentRunJSON.data(using: .utf8) else { return nil }
            guard let run = try? JSONDecoder().decode(AgentRun.self, from: data),
                  run.schemaVersion > 0, run.schemaVersion <= AgentRun.currentSchemaVersion else { return nil }
            return run
        }
        set {
            agentRunJSON = newValue.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}
'''
CHECKS = r'''
import Foundation
@main struct CacheChecks {
    @MainActor static func main() {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name)
            checks += 1
        }
        var decodes = 0
        let cache = HanlinAgentRunReadCache(capacity: 2, decode: { row in
            decodes += 1
            return row.agentRun
        })
        let first = ChatMessages(), second = ChatMessages(), third = ChatMessages()
        let run = AgentRun(id: UUID(), modelID: "Café שלום 👋🏽")
        for row in [first, second, third] { row.agentRun = run }
        check(cache.run(for: first)?.id == run.id, "initial decode")
        check(cache.run(for: first)?.id == run.id && decodes == 1, "unchanged JSON cache hit")
        _ = cache.run(for: second)
        _ = cache.run(for: first)
        _ = cache.run(for: third)
        _ = cache.run(for: first)
        check(decodes == 3, "LRU preserves recently used first row")
        _ = cache.run(for: second)
        check(decodes == 4, "LRU evicts second row independently of identical JSON")
        first.agentRunJSON = "{malformed"
        check(cache.run(for: first) == nil, "malformed invalidates prior value")
        let afterMalformed = decodes
        check(cache.run(for: first) == nil && decodes == afterMalformed, "negative decode cache")
        first.agentRunJSON = nil
        check(cache.run(for: first) == nil && decodes == afterMalformed, "nil bypasses decoder")
        first.agentRun = run
        check(cache.run(for: first)?.id == run.id && decodes == afterMalformed + 1, "valid replacement after nil")
        let composed = first.agentRunJSON!
        first.agentRunJSON = composed.replacingOccurrences(of: "é", with: "e\u{301}")
        check(first.agentRunJSON == composed, "fixture is canonically equal Swift String")
        _ = cache.run(for: first)
        check(decodes == afterMalformed + 2, "different exact UTF8 invalidates cache")
        first.agentRunJSON = " " + first.agentRunJSON!
        _ = cache.run(for: first)
        check(decodes == afterMalformed + 3, "whitespace replacement invalidates cache")
        first.agentRun = AgentRun(schemaVersion: 99, id: run.id, modelID: "unsupported")
        check(cache.run(for: first) == nil, "original schema rejection preserved")
        let afterSchema = decodes
        check(cache.run(for: first) == nil && decodes == afterSchema, "schema failure negative cache")
        var budgetDecodes = 0
        let budget = HanlinAgentRunReadCache(capacity: 4, maximumSourceBytes: 1, decode: { row in
            budgetDecodes += 1; return row.agentRun
        })
        _ = budget.run(for: second); _ = budget.run(for: second)
        check(budgetDecodes == 2, "oversized snapshot never retained")
        var boundedDecodes = 0
        let byteLimit = second.agentRunJSON!.utf8.count
        let bounded = HanlinAgentRunReadCache(capacity: 4, maximumSourceBytes: byteLimit, decode: { row in
            boundedDecodes += 1; return row.agentRun
        })
        _ = bounded.run(for: second); _ = bounded.run(for: third); _ = bounded.run(for: second)
        check(boundedDecodes == 3, "aggregate byte budget evicts oldest value")
        let nilCache = HanlinAgentRunReadCache(capacity: 1, decode: { row in
            boundedDecodes += 1; return row.agentRun
        })
        _ = nilCache.run(for: second)
        let nilRow = ChatMessages()
        for _ in 0..<100 { _ = nilCache.run(for: nilRow) }
        _ = nilCache.run(for: second)
        check(boundedDecodes == 4, "nil rows do not evict useful values")
        let memoryCache = HanlinAgentRunReadCache()
        weak var released: ChatMessages?
        do {
            let row = ChatMessages(); row.agentRun = run; released = row
            _ = memoryCache.run(for: row)
        }
        check(released == nil, "cache never retains model objects")
        print("PASS: \(checks) original-source AgentRun cache checks")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='hanlin-agent-run-cache-') as directory:
    temporary = Path(directory)
    fixture = temporary / 'Fixture.swift'
    checks = temporary / 'Checks.swift'
    executable = temporary / 'cache-checks.exe'
    fixture.write_text(FIXTURE, encoding='utf-8')
    checks.write_text(CHECKS, encoding='utf-8')
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', str(fixture), str(SOURCE), str(checks), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
