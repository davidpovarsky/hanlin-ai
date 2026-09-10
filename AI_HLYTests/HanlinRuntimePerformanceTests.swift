import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptStore
import HanlinScriptingApplicationRuntime
import HanlinScriptingSDK
import XCTest
@testable import AI_Hanlin

/// Unit-level performance regression suite measuring deterministic runtime engines,
/// JavaScriptCore, QuickJS, multi-engine switching, and package store loading.
final class HanlinRuntimePerformanceTests: XCTestCase {
    private static let sampleIterationCount = 5

    private func measureOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = Self.sampleIterationCount
        return options
    }

    private func emitSample(
        flowNumber: Int,
        flowName: String,
        category: String,
        metric: String,
        unit: String,
        samples: [Double],
        classification: String = "informational"
    ) {
        guard !samples.isEmpty else { return }
        let count = Double(samples.count)
        let mean = samples.reduce(0.0, +) / count
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let variance = samples.reduce(0.0) { $0 + pow($1 - mean, 2.0) } / max(1.0, count - 1.0)
        let stdDev = sqrt(variance)
        let minVal = sorted.first ?? 0.0
        let maxVal = sorted.last ?? 0.0

        let payload: [String: Any] = [
            "flow_number": flowNumber,
            "flow_name": flowName,
            "category": category,
            "metric": metric,
            "unit": unit,
            "sample_count": samples.count,
            "samples": samples,
            "mean": mean,
            "median": median,
            "std_dev": stdDev,
            "min": minVal,
            "max": maxVal,
            "classification": classification,
            "status": "PASS"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let jsonStr = String(data: data, encoding: .utf8) {
            print("HANLIN_PERF_SAMPLE: \(jsonStr)")
        }
    }

    // MARK: - Flow 4: Initialize Default/Simple JavaScript Runtime (JavaScriptCore)

    func testFlow4_JavaScriptCoreInitializationPerformance() throws {
        var recordedSamples: [Double] = []
        var sessions: [HanlinJavaScriptCoreSession] = []
        defer {
            for s in sessions {
                Task { await s.dispose() }
            }
        }

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false), XCTMemoryMetric()],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let session = try HanlinJavaScriptCoreSession(configuration: .scriptingCompatibility)
                sessions.append(session)
            } catch {
                XCTFail("JavaScriptCore initialization failed: \(error)")
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 4,
            flowName: "JavaScriptCore Initialization",
            category: "Runtime Engine",
            metric: "session_init_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 5: Execute Tiny Deterministic Script in JavaScriptCore

    func testFlow5_JavaScriptCoreDeterministicExecutionPerformance() async throws {
        var recordedSamples: [Double] = []
        let session = try HanlinJavaScriptCoreSession(configuration: .scriptingCompatibility)
        defer { Task { await session.dispose() } }

        let program = """
        let counter = 0;
        AssistantTool.registerExecuteTool((parameters) => {
            counter += 1;
            let sum = 0;
            for (let i = 0; i < 500; i++) { sum += i; }
            return {
                success: true,
                message: String(sum + counter)
            };
        });
        """
        try await session.loadProgram(program, filename: "jsc_perf.js", expectedToolCount: 1)

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false)],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            let exp = expectation(description: "jsc-invoke")
            Task {
                do {
                    let result = try await session.invoke(toolIndex: 0, parameters: .object([:]))
                    guard case let .object(members) = result,
                          case let .bool(success)? = members["success"],
                          success else {
                        XCTFail("JSC deterministic invocation returned unsuccessful result")
                        exp.fulfill()
                        return
                    }
                    exp.fulfill()
                } catch {
                    XCTFail("JSC execution threw error: \(error)")
                    exp.fulfill()
                }
            }
            wait(for: [exp], timeout: 10.0)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 5,
            flowName: "JavaScriptCore Deterministic Execution",
            category: "Runtime Engine",
            metric: "script_execution_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 6: Initialize Major Runtime Engine (QuickJS)

    func testFlow6_QuickJSInitializationPerformance() throws {
        var recordedSamples: [Double] = []
        var sessions: [HanlinQuickJSSession] = []
        defer {
            for s in sessions {
                Task { await s.dispose() }
            }
        }

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false), XCTMemoryMetric()],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let session = try HanlinQuickJSSession(configuration: .phase2A)
                sessions.append(session)
            } catch {
                XCTFail("QuickJS initialization failed: \(error)")
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 6,
            flowName: "QuickJS Initialization",
            category: "Runtime Engine",
            metric: "session_init_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 7: Execute Tiny Deterministic Operation in QuickJS

    func testFlow7_QuickJSDeterministicExecutionPerformance() async throws {
        var recordedSamples: [Double] = []
        let session = try HanlinQuickJSSession(configuration: .phase2A)
        defer { Task { await session.dispose() } }

        let program = """
        let counter = 0;
        AssistantTool.registerExecuteTool((parameters) => {
            counter += 1;
            let sum = 0;
            for (let i = 0; i < 500; i++) { sum += i; }
            return {
                success: true,
                message: String(sum + counter)
            };
        });
        """
        try await session.loadProgram(program, filename: "quickjs_perf.js", expectedToolCount: 1)

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false)],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            let exp = expectation(description: "quickjs-invoke")
            Task {
                do {
                    let result = try await session.invoke(toolIndex: 0, parameters: .object([:]))
                    guard case let .object(members) = result,
                          case let .bool(success)? = members["success"],
                          success else {
                        XCTFail("QuickJS deterministic invocation returned unsuccessful result")
                        exp.fulfill()
                        return
                    }
                    exp.fulfill()
                } catch {
                    XCTFail("QuickJS execution threw error: \(error)")
                    exp.fulfill()
                }
            }
            wait(for: [exp], timeout: 10.0)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 7,
            flowName: "QuickJS Deterministic Execution",
            category: "Runtime Engine",
            metric: "script_execution_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 8: Runtime Engine Switch Cost (JSC <-> QuickJS)

    func testFlow8_MultiEngineRuntimeSwitchPerformance() async throws {
        var recordedSamples: [Double] = []
        let jsc = try HanlinJavaScriptCoreSession(configuration: .scriptingCompatibility)
        let qjs = try HanlinQuickJSSession(configuration: .phase2A)
        defer {
            Task {
                await jsc.dispose()
                await qjs.dispose()
            }
        }

        let program = """
        AssistantTool.registerExecuteTool((parameters) => ({
            success: true,
            message: "switched"
        }));
        """
        try await jsc.loadProgram(program, filename: "jsc_switch.js", expectedToolCount: 1)
        try await qjs.loadProgram(program, filename: "qjs_switch.js", expectedToolCount: 1)

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false)],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            let exp = expectation(description: "engine-switch")
            Task {
                do {
                    let r1 = try await jsc.invoke(toolIndex: 0, parameters: .object([:]))
                    let r2 = try await qjs.invoke(toolIndex: 0, parameters: .object([:]))
                    guard case let .object(m1) = r1, case let .bool(s1)? = m1["success"], s1,
                          case let .object(m2) = r2, case let .bool(s2)? = m2["success"], s2 else {
                        XCTFail("Multi-engine switch invocation failed")
                        exp.fulfill()
                        return
                    }
                    exp.fulfill()
                } catch {
                    XCTFail("Multi-engine switch error: \(error)")
                    exp.fulfill()
                }
            }
            wait(for: [exp], timeout: 10.0)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 8,
            flowName: "Runtime Switch Cost (JSC <-> QuickJS)",
            category: "Runtime Engine",
            metric: "sequential_switch_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 9: Deterministic Local Package Store Import & Manifest Parse

    func testFlow9_DeterministicPackageStoreImportPerformance() throws {
        var recordedSamples: [Double] = []
        let fixtureDir = try bundledFixtureDirectory("ValidEcho")

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false), XCTMemoryMetric()],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            let tempDir = FileManager.default.temporaryDirectory.appending(
                path: "perf-import-\(UUID().uuidString.lowercased())",
                directoryHint: .isDirectory
            )
            do {
                try FileManager.default.copyItem(at: fixtureDir, to: tempDir)
                let loaded = try HanlinScriptPackageLoader.load(packageDirectory: tempDir)
                XCTAssertEqual(loaded.manifest.packageID.rawValue, "hanlin.test.echo")
                try? FileManager.default.removeItem(at: tempDir)
            } catch {
                XCTFail("Deterministic package store import failed: \(error)")
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 9,
            flowName: "Deterministic Package Store Import & Manifest Parse",
            category: "Storage / Package",
            metric: "package_import_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 10: Package Tool Execution on Already Installed Package

    func testFlow10_InstalledPackageProviderExecutionPerformance() async throws {
        let registry = HanlinScriptingProviderRegistry()
        let fixtureDir = try materializedFixtureDirectory("ValidEcho")
        defer {
            try? FileManager.default.removeItem(at: fixtureDir)
            Task { await registry.unloadAll() }
        }

        _ = try await registry.loadPackage(at: fixtureDir, trust: .bundledTrusted)
        let snapshots = await registry.snapshots()
        guard let firstRoute = snapshots.first?.route else {
            XCTFail("No provider snapshots registered for ValidEcho fixture")
            return
        }

        var recordedSamples: [Double] = []
        for _ in 0..<Self.sampleIterationCount {
            let start = CFAbsoluteTimeGetCurrent()
            let result = try await registry.execute(
                route: firstRoute,
                argumentsJSON: #"{"text":"perf-sample"}"#
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.message, "script:perf-sample")
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 10,
            flowName: "Installed Package Tool Execution",
            category: "Scripting Provider",
            metric: "provider_execution_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Memory Stability & Leak Bounds Under Repeated Lifecycle Cycles

    func testRuntimeMemoryStabilityUnderRepeatedExecutionCycles() async throws {
        let initialMemoryMB = currentResidentMemoryMB()
        let cycleCount = 50

        for _ in 0..<cycleCount {
            let jsc = try HanlinJavaScriptCoreSession(configuration: .scriptingCompatibility)
            try await jsc.loadProgram(
                "AssistantTool.registerExecuteTool(() => ({ success: true, message: 'ok' }));",
                filename: "mem.js",
                expectedToolCount: 1
            )
            _ = try await jsc.invoke(toolIndex: 0, parameters: .object([:]))
            await jsc.dispose()

            let qjs = try HanlinQuickJSSession(configuration: .phase2A)
            try await qjs.loadProgram(
                "AssistantTool.registerExecuteTool(() => ({ success: true, message: 'ok' }));",
                filename: "mem_q.js",
                expectedToolCount: 1
            )
            _ = try await qjs.invoke(toolIndex: 0, parameters: .object([:]))
            await qjs.dispose()
        }

        let finalMemoryMB = currentResidentMemoryMB()
        let memoryDeltaMB = max(0.0, finalMemoryMB - initialMemoryMB)

        emitSample(
            flowNumber: 0,
            flowName: "Memory Stability (50 Lifecycle Cycles)",
            category: "Memory / Stability",
            metric: "memory_growth_delta",
            unit: "MB",
            samples: [memoryDeltaMB],
            classification: "hard_gate"
        )

        // Hard gate: 50 cycles of create->invoke->dispose must not leak runaway memory (> 50 MB)
        XCTAssertLessThan(
            memoryDeltaMB,
            50.0,
            "Memory grew monotonically by \(memoryDeltaMB) MB across \(cycleCount) cycles (hard gate: < 50MB)"
        )
    }

    // MARK: - Helpers

    private func currentResidentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }

    private func bundledFixtureDirectory(_ name: String) throws -> URL {
        let bundle = Bundle(for: HanlinRuntimePerformanceTests.self)
        let roots = [
            bundle.url(
                forResource: "ScriptingFixtures",
                withExtension: "bundle",
                subdirectory: "Fixtures"
            ),
            bundle.url(forResource: "ScriptingFixtures", withExtension: "bundle")
        ].compactMap { $0 }
        guard let root = roots.first(where: {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }) else {
            throw HanlinScriptingError.unavailableProvider("fixture_bundle_missing")
        }
        let directory = root.appending(path: name, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            throw HanlinScriptingError.unavailableProvider("fixture_missing_\(name)")
        }
        return directory
    }

    private func materializedFixtureDirectory(_ name: String) throws -> URL {
        let source = try bundledFixtureDirectory(name)
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-script-fixture-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
