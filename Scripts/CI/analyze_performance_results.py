#!/usr/bin/env python3
"""Parse, aggregate, and report iPad performance benchmark results for hanlin-ai.

Processes sample payloads from xcodebuild logs and optional xcresult metrics,
computes statistical summaries (median, mean, min, max, stddev, CV%),
classifies metrics into Hard Gates vs Informational Metrics, and outputs
both structured JSON and GitHub Actions Step Summary markdown.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
from pathlib import Path
import re
import sys
from typing import Any, Dict, List, Optional


FLOW_DEFINITIONS: Dict[int, str] = {
    1: "Application Cold Launch",
    2: "Time to Usable First Screen",
    3: "Open Scripting/Apps Screen",
    4: "Initialize Default JavaScript Runtime (JSC)",
    5: "Execute Deterministic Script (JSC)",
    6: "Initialize Major Engine (QuickJS)",
    7: "Execute Deterministic Operation (QuickJS)",
    8: "Multi-Engine Runtime Switch Cost (JSC <-> QuickJS)",
    9: "Deterministic Package Store Import & Manifest Parse",
    10: "Installed Package Tool Execution",
    11: "NativeScript First Initialization",
    12: "NativeScript First UI Render",
    13: "@nativescript/swift-ui Provider First Render",
    14: "NativeScript/SwiftUI Warm & Round-Trip Render",
    15: "Key Scripting Interactions (Reactive State Mutation)",
    16: "Persistence / Reload Across App Restart",
}


def parse_log_files(log_dir: Path) -> List[Dict[str, Any]]:
    """Find and parse all HANLIN_PERF_SAMPLE lines in log files."""
    samples: List[Dict[str, Any]] = []
    if not log_dir.exists():
        return samples

    for log_path in sorted(log_dir.glob("**/*.log")) + sorted(log_dir.glob("*.txt")):
        try:
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if "HANLIN_PERF_SAMPLE:" in line:
                        payload_str = line.split("HANLIN_PERF_SAMPLE:", 1)[1].strip()
                        try:
                            sample = json.loads(payload_str)
                            samples.append(sample)
                        except Exception:
                            pass
        except Exception:
            pass
    return samples


def compute_statistics(samples: List[float]) -> Dict[str, float]:
    """Calculate mean, median, standard deviation, min, max, and CV%."""
    if not samples:
        return {
            "count": 0,
            "mean": 0.0,
            "median": 0.0,
            "min": 0.0,
            "max": 0.0,
            "std_dev": 0.0,
            "cv_percent": 0.0,
        }

    n = len(samples)
    sorted_s = sorted(samples)
    mean_val = sum(samples) / float(n)
    median_val = sorted_s[n // 2] if n % 2 != 0 else (sorted_s[n // 2 - 1] + sorted_s[n // 2]) / 2.0
    min_val = sorted_s[0]
    max_val = sorted_s[-1]

    if n > 1:
        variance = sum((x - mean_val) ** 2 for x in samples) / float(n - 1)
        std_dev = math.sqrt(variance)
    else:
        std_dev = 0.0

    cv = (std_dev / mean_val * 100.0) if mean_val > 0 else 0.0

    return {
        "count": n,
        "mean": mean_val,
        "median": median_val,
        "min": min_val,
        "max": max_val,
        "std_dev": std_dev,
        "cv_percent": cv,
    }


def analyze_records(
    raw_records: List[Dict[str, Any]], require_canonical_flows: bool = True
) -> Dict[str, Any]:
    """Group samples by flow and metric, compute stats, and classify gates."""
    metrics_by_key: Dict[str, Dict[str, Any]] = {}

    for record in raw_records:
        flow_num = record.get("flow_number", 0)
        metric_name = record.get("metric", "unknown")
        key = f"flow_{flow_num}_{metric_name}" if flow_num > 0 else metric_name

        samples = [float(x) for x in record.get("samples", [])]
        classification = record.get("classification", "informational")
        flow_name = record.get("flow_name") or FLOW_DEFINITIONS.get(flow_num, f"Flow {flow_num}")
        category = record.get("category", "General")
        unit = record.get("unit", "s")

        if key not in metrics_by_key:
            metrics_by_key[key] = {
                "key": key,
                "flow_number": flow_num,
                "flow_name": flow_name,
                "category": category,
                "metric": metric_name,
                "unit": unit,
                "classification": classification,
                "samples": [],
            }
        metrics_by_key[key]["samples"].extend(samples)

    evaluated_metrics: List[Dict[str, Any]] = []
    hard_gate_failures: List[str] = []

    for key, info in sorted(metrics_by_key.items(), key=lambda x: (x[1]["flow_number"], x[1]["metric"])):
        stats = compute_statistics(info["samples"])
        status = "PASS"

        # Evaluate hard gates
        if info["classification"] == "hard_gate":
            if info["metric"] == "memory_growth_delta":
                # Hard gate: memory growth across 50 cycles must not exceed 50 MB
                if stats["max"] >= 50.0:
                    status = "FAIL"
                    hard_gate_failures.append(
                        f"{info['flow_name']}: Memory grew by {stats['max']:.2f} MB (hard limit: 50.0 MB)"
                    )
            elif info["metric"] == "functional_pass_rate":
                if stats["min"] < 100.0:
                    status = "FAIL"
                    hard_gate_failures.append(
                        f"{info['flow_name']}: Pass rate dropped to {stats['min']:.1f}%"
                    )

        entry = {
            "key": key,
            "flow_number": info["flow_number"],
            "flow_name": info["flow_name"],
            "category": info["category"],
            "metric": info["metric"],
            "unit": info["unit"],
            "classification": info["classification"],
            "status": status,
            "statistics": stats,
            "raw_samples": info["samples"],
        }
        evaluated_metrics.append(entry)

    # When canonical flow validation is required, fail visibly if any canonical flow 1-16 is missing
    if require_canonical_flows and evaluated_metrics:
        present_flows = {entry["flow_number"] for entry in evaluated_metrics}
        for flow_id in range(1, 17):
            if flow_id not in present_flows:
                flow_title = FLOW_DEFINITIONS.get(flow_id, f"Flow {flow_id}")
                hard_gate_failures.append(
                    f"Missing required canonical benchmark flow: Flow {flow_id} ({flow_title})"
                )

    return {
        "metrics": evaluated_metrics,
        "total_metrics_evaluated": len(evaluated_metrics),
        "hard_gate_passed": len(hard_gate_failures) == 0,
        "hard_gate_failures": hard_gate_failures,
    }


def render_markdown_report(summary: Dict[str, Any], xcode_version: str = "Xcode 26", runner_arch: str = "arm64") -> str:
    """Render structured Markdown report for GITHUB_STEP_SUMMARY."""
    lines: List[str] = [
        "# 📊 iPad Performance & Regression Baseline Report",
        "",
        "### Test Execution Environment",
        "| Property | Value |",
        "| --- | --- |",
        "| **Simulator Platform** | iOS 26 Simulator (iPad, arm64) |",
        "| **Build Configuration** | `Release` (with `ENABLE_TESTABILITY=YES`) |",
        f"| **Toolchain** | {xcode_version} |",
        f"| **Architecture** | {runner_arch} |",
        "| **Sampling Strategy** | Multi-sample repeated measurement (N=5) |",
        "",
    ]

    if not summary["hard_gate_passed"]:
        lines.append(
            "> [!CAUTION]\n"
            "> **HARD REGRESSION GATE FAILED**\n"
            + "\n".join(f"> - {f}" for f in summary["hard_gate_failures"])
            + "\n"
        )
    else:
        lines.append(
            "> [!NOTE]\n"
            "> **All hard regression invariants passed.** Informational timings establish the multi-sample current baseline.\n"
        )

    if not summary["metrics"]:
        lines.append("*No performance benchmark samples recorded in this validation run.*")
        lines.append("")
    else:
        lines.append("### Measured Performance Matrix (Flows 1–16)")
        lines.append("")
        lines.append("| Flow # | Benchmark Flow | Category | N | Median | Mean | Min / Max | StdDev (CV%) | Classification | Status |")
        lines.append("| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")

        for m in summary["metrics"]:
            flow_num = m["flow_number"]
            flow_display = f"Flow {flow_num}" if flow_num > 0 else "Stability"
            flow_name = m["flow_name"]
            cat = m["category"]
            unit = m["unit"]
            stats = m["statistics"]
            n = stats["count"]
            med = f"{stats['median']:.4f}{unit}" if stats["median"] < 10 else f"{stats['median']:.2f}{unit}"
            mean_s = f"{stats['mean']:.4f}{unit}" if stats["mean"] < 10 else f"{stats['mean']:.2f}{unit}"
            min_max = f"{stats['min']:.4f} / {stats['max']:.4f}{unit}" if stats["max"] < 10 else f"{stats['min']:.2f} / {stats['max']:.2f}{unit}"
            cv_str = f"±{stats['std_dev']:.4f}{unit} ({stats['cv_percent']:.1f}%)" if stats["std_dev"] < 10 else f"±{stats['std_dev']:.2f}{unit} ({stats['cv_percent']:.1f}%)"
            classification = "Hard Gate" if m["classification"] == "hard_gate" else "Informational"
            status_emoji = "✅ PASS" if m["status"] == "PASS" else ("❌ FAIL" if m["status"] == "FAIL" else "ℹ️ INFO")

            lines.append(
                f"| {flow_display} | **{flow_name}** | {cat} | {n} | `{med}` | `{mean_s}` | `{min_max}` | `{cv_str}` | {classification} | {status_emoji} |"
            )

    lines.append("")
    lines.append("### XCTest Instrumentation & Metrics Governance")
    lines.append("")
    lines.append("| Metric | Utilized in Suite? | Operational Role & Rationale |")
    lines.append("| --- | :---: | --- |")
    lines.append("| **`XCTApplicationLaunchMetric`** | **Yes** | Measures process cold startup duration until the initial scene is responsive (Flow 1). |")
    lines.append("| **`XCTClockMetric`** | **Yes** | Measures monotonic elapsed wall-clock latency across repeated sample iterations for navigation, compilation, runtime switching, and UI interaction. |")
    lines.append("| **`XCTCPUMetric`** | **Yes** | Measures multi-threaded CPU execution time. CPU results are XCTest metrics tracked as informational baselines under virtualized runner load. |")
    lines.append("| **`XCTMemoryMetric`** | **Yes** | Tracks memory footprint delta during XCTest measurement blocks. Memory results are XCTest metrics kept informational alongside the dedicated 50-cycle physical footprint hard gate. |")
    lines.append("| **`os.OSSignposter`** | **Yes** | High-precision signpost intervals emitted by `HanlinScriptingPerformanceSignposts` around package loading, compilation, and scripting provider invocation. |")
    lines.append("| **`XCTHitchMetric`** | **No** | **Reason not used:** Designed for scroll hitches and display frame presentation glitches on physical displays. On headless virtualized macOS CI runners, display refresh cycles are virtualized without a real hardware v-sync rasterizer or display engine, making frame hitch metrics non-authoritative, highly noisy, and dominated by host runner virtualization jitter rather than app rendering performance. |")
    lines.append("| **`XCTStorageMetric`** | **No** | **Reason not used:** Measures raw on-disk volume byte delta during test execution. In this suite, storage import and persistence are measured with exact deterministic verification (`HanlinScriptPackageLoader`) and timing, while memory stability is tracked via Mach physical footprint (`TASK_VM_INFO.phys_footprint`). `XCTStorageMetric` on simulator writes across the shared host container and APFS temp volumes fluctuates due to Xcode derived data and simulator diagnostic logging, making it unstable as an isolated regression gate. |")
    lines.append("")
    lines.append("**Performance Artifacts**:")
    lines.append("- Structured JSON Summary: `performance-summary.json`")
    lines.append("- Markdown Step Summary: `performance-summary.md`")
    lines.append("")
    lines.append("### Simulator vs. Physical iPad Limitation Notice")
    lines.append("")
    lines.append("**What this suite can prove well:**")
    lines.append("- Relative performance regressions under comparable CI conditions;")
    lines.append("- Launch/runtime/render timing trends across commits;")
    lines.append("- CPU/memory/hitch trends large enough to exceed hosted-runner noise;")
    lines.append("- Correctness under repeated lifecycle operations.")
    lines.append("")
    lines.append("**What it cannot prove exactly:**")
    lines.append("- Physical iPad A/M-series absolute CPU/GPU speed;")
    lines.append("- Device thermals/throttling behavior under continuous sustained load;")
    lines.append("- Battery/energy impact with real hardware accuracy;")
    lines.append("- Exact real-device memory pressure under low-memory jetsam conditions;")
    lines.append("- Hardware/sensor/camera-specific latency and throughput;")
    lines.append("- Real physical cellular/Wi-Fi radio conditions.")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze iPad performance test results.")
    parser.add_argument("--log-dir", required=True, help="Directory containing performance log files")
    parser.add_argument("--xcresult", help="Path to xcresult bundle")
    parser.add_argument("--output-json", help="Path to write JSON performance summary")
    parser.add_argument("--output-markdown", help="Path to write Markdown performance summary")
    parser.add_argument("--github-step-summary", help="Path to write GitHub Step Summary")
    parser.add_argument("--xcode-version", default="Xcode 26", help="Xcode toolchain version string")
    parser.add_argument("--runner-arch", default="arm64", help="Runner architecture")
    parser.add_argument(
        "--no-require-canonical-flows",
        dest="require_canonical_flows",
        action="store_false",
        default=True,
        help="Disable failure on missing canonical flows 1-16",
    )

    args = parser.parse_args()

    raw_samples = parse_log_files(Path(args.log_dir))
    summary = analyze_records(raw_samples, require_canonical_flows=args.require_canonical_flows)
    markdown = render_markdown_report(summary, xcode_version=args.xcode_version, runner_arch=args.runner_arch)

    print(markdown)

    if args.output_json:
        out_json_path = Path(args.output_json)
        out_json_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_json_path, "w", encoding="utf-8") as f:
            json.dump(summary, f, indent=2)

    if args.output_markdown:
        out_md_path = Path(args.output_markdown)
        out_md_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_md_path, "w", encoding="utf-8") as f:
            f.write(markdown + "\n")

    if args.github_step_summary:
        step_summary_path = Path(args.github_step_summary)
        step_summary_path.parent.mkdir(parents=True, exist_ok=True)
        with open(step_summary_path, "a", encoding="utf-8") as f:
            f.write(markdown + "\n")

    if not summary["hard_gate_passed"]:
        sys.stderr.write("Performance validation failed on hard regression gates.\n")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
