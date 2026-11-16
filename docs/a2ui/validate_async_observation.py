#!/usr/bin/env python3
"""Run the actual generic test wait/quiet helpers with real Swift AsyncStream.

This is a portable observation-harness regression, not an A2UI SDK substitute.
No Testing module, renderer stubs, package resolution or native job is used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / "AI_HLYTests/A2UITests.swift"

DRIVER = r'''
private final class ProbeState: Sendable {
    let events = Mutex<[Int]>([])
    let terminations = Mutex<[String]>([])
}
private final class ProbeRecorder: Sendable {
    let state = ProbeState()
    let stream: AsyncStream<Int>
    private let continuation: AsyncStream<Int>.Continuation
    init() {
        (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        let state = state
        continuation.onTermination = { reason in
            let value: String
            switch reason {
            case .cancelled: value = "cancelled"
            case .finished: value = "finished"
            @unknown default: value = "unknown"
            }
            state.terminations.withLock { $0.append(value) }
        }
    }
    @discardableResult func record(_ value: Int) -> Bool {
        state.events.withLock { $0.append(value) }
        if case .terminated = continuation.yield(value) { return false }
        return true
    }
    var count: Int { state.events.withLock { $0.count } }
    var terminations: [String] { state.terminations.withLock { $0 } }
    deinit { continuation.finish() }
}
@main private enum Probe {
    static func main() async throws {
        let old = ProbeRecorder()
        do {
            _ = try await nextA2UIValue(old.stream, timeout: .milliseconds(20))
            throw A2UICheckFailure(description: "Old negative wait unexpectedly returned")
        } catch A2UIWaitError.deadline {}
        try requireA2UI(old.terminations == ["cancelled"], "Reader cancellation did not terminate the actual stream")
        try requireA2UI(!old.record(7), "Cancelled stream still accepted a yield")
        do {
            _ = try await nextA2UIValue(old.stream, timeout: .milliseconds(100))
            throw A2UICheckFailure(description: "Cancelled stream produced a value")
        } catch A2UIWaitError.ended {}
        print("EXECUTED_PASS reproducesTimeoutCancellationThenEnded")

        let healthy = ProbeRecorder()
        try await requireA2UIQuiet(expectedCount: 0, duration: .milliseconds(20),
                                  count: { healthy.count }, failureMessage: "Unexpected initial event")
        try requireA2UI(healthy.terminations.isEmpty, "Quiet observation terminated the stream")
        try requireA2UI(healthy.record(11), "First positive yield rejected after quiet observation")
        try requireA2UI(try await nextA2UIValue(healthy.stream) == 11, "First positive value missing")
        try await requireA2UIQuiet(expectedCount: 1, duration: .milliseconds(20),
                                  count: { healthy.count }, failureMessage: "Unexpected second event")
        try requireA2UI(healthy.record(12), "Second positive yield rejected")
        try requireA2UI(try await nextA2UIValue(healthy.stream) == 12, "Second positive value missing")
        try requireA2UI(healthy.terminations.isEmpty && healthy.count == 2, "Healthy stream was consumed/cancelled")
        print("EXECUTED_PASS quietObservationPreservesLaterPositiveDelivery")

        let unexpected = ProbeRecorder()
        let delivery = Task {
            try await Task.sleep(for: .milliseconds(5))
            unexpected.record(99)
        }
        defer { delivery.cancel() }
        do {
            try await requireA2UIQuiet(expectedCount: 0, duration: .milliseconds(40),
                                      count: { unexpected.count }, failureMessage: "CONTROL_UNEXPECTED_EVENT")
            throw A2UICheckFailure(description: "Quiet observation hid an unexpected event")
        } catch let error as A2UICheckFailure where error.description == "CONTROL_UNEXPECTED_EVENT" {}
        try await delivery.value
        try requireA2UI(unexpected.terminations.isEmpty, "Failed observation cancelled the stream")
        try requireA2UI(try await nextA2UIValue(unexpected.stream) == 99, "Unexpected event was discarded")
        print("EXECUTED_PASS unexpectedEventFailsObservationAndRemainsDeliverable")
    }
}
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = TEST.read_text(encoding="utf-8")
    checks = source.split("private struct A2UICheckFailure", 1)[1].split("private let diagnosticCanary", 1)[0]
    waits = source.split("private enum A2UIWaitError", 1)[1].split("#if HANLIN_A2UI_PORTABLE_RUNNER", 1)[0]
    helpers = "private struct A2UICheckFailure" + checks + "private enum A2UIWaitError" + waits
    compiler = shutil.which("swiftc")
    if not compiler:
        raise RuntimeError("Actual Swift compiler is required")
    scratch = Path(tempfile.mkdtemp(prefix="hanlin-a2ui-observer-")).resolve()
    temp_root = Path(tempfile.gettempdir()).resolve()
    if scratch.parent != temp_root or not scratch.name.startswith("hanlin-a2ui-observer-"):
        raise RuntimeError("Unsafe temporary observation directory")
    try:
        probe = scratch / "probe.swift"
        probe.write_text("import Foundation\nimport Synchronization\n" + helpers + DRIVER, encoding="utf-8")
        binary = scratch / "probe.exe"
        subprocess.run([compiler, "-swift-version", "6", "-strict-concurrency=complete",
                        "-parse-as-library", str(probe), "-o", str(binary)], check=True)
        run = subprocess.run([str(binary)], capture_output=True, text=True, check=True)
        results = [line for line in run.stdout.splitlines() if line.startswith("EXECUTED_PASS ")]
        if len(results) != 3:
            raise RuntimeError("Expected all3 real AsyncStream observation regressions")
        result = {"status": "EXECUTED_PASS", "checks": results,
                  "actual_helpers_sha256": hashlib.sha256(helpers.encode()).hexdigest(),
                  "test_source_sha256": hashlib.sha256(TEST.read_bytes()).hexdigest(),
                  "swift": subprocess.check_output([compiler, "--version"], text=True).strip(),
                  "scope": "Real Swift AsyncStream and actual generic test helpers; no A2UI SDK/Testing/Apple API proof"}
        if args.output:
            output = args.output.resolve()
            if not output.is_relative_to(ROOT / "docs/a2ui/evidence"):
                raise RuntimeError("Retain results only inside owned A2UI evidence")
            output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(json.dumps(result, indent=2))
    finally:
        # Only the freshly-created, resolved, prefix-checked directory above is removed.
        if scratch.parent != temp_root or not scratch.name.startswith("hanlin-a2ui-observer-"):
            raise RuntimeError("Unsafe observation cleanup path")
        shutil.rmtree(scratch)


if __name__ == "__main__":
    main()
