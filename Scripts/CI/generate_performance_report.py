#!/usr/bin/env python3
"""Generate structured CI performance report, cold/warm comparisons, and GitHub Step Summary.

Outputs `ci-performance-report.json` and renders markdown for GITHUB_STEP_SUMMARY.
Clearly distinguishes between:
- Actual measured Job duration and Step durations (seconds)
- Authentic test execution vs reused test evidence (REUSED_VERIFIED_PASS)
- Exact cache hits vs compatible restores vs cold misses
- Saved cache vs skipped saves (SAVE_SKIPPED vs SAVE_CREATED)
- Side-by-side Cold vs Warm run comparisons (when baseline/comparison reports are provided)
- Estimated time saved (strictly labeled as ESTIMATED)
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional


def parse_duration_file(path: Path) -> Optional[int]:
    """Read an integer duration in seconds from a text file."""
    if path.is_file():
        try:
            return int(path.read_text(encoding="utf-8").strip())
        except (ValueError, OSError):
            pass
    return None


def read_cache_mode_log(log_path: Path) -> Dict[str, str]:
    """Parse cache-mode.log file into key-value pairs."""
    result = {}
    if log_path.is_file():
        try:
            for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    result[k.strip()] = v.strip()
        except OSError:
            pass
    return result


def compare_cold_and_warm(cold_report: Dict[str, Any], warm_report: Dict[str, Any]) -> Dict[str, Any]:
    """Produce detailed delta and comparison between a cold and a warm run."""
    cold_total = cold_report.get("total_active_seconds", 0)
    warm_total = warm_report.get("total_active_seconds", 0)
    diff_seconds = cold_total - warm_total
    percent_reduction = (diff_seconds / cold_total * 100.0) if cold_total > 0 else 0.0

    step_deltas: Dict[str, Dict[str, Any]] = {}
    cold_steps = cold_report.get("step_durations_seconds", {})
    warm_steps = warm_report.get("step_durations_seconds", {})
    all_step_keys = sorted(set(cold_steps.keys()) | set(warm_steps.keys()))

    for k in all_step_keys:
        c_dur = cold_steps.get(k, 0)
        w_dur = warm_steps.get(k, 0)
        step_deltas[k] = {
            "cold_seconds": c_dur,
            "warm_seconds": w_dur,
            "saved_seconds": c_dur - w_dur,
        }

    return {
        "cold_run_id": cold_report.get("run_id", "cold"),
        "warm_run_id": warm_report.get("run_id", "warm"),
        "cold_total_seconds": cold_total,
        "warm_total_seconds": warm_total,
        "measured_saved_seconds": diff_seconds,
        "percent_reduction": round(percent_reduction, 2),
        "step_deltas": step_deltas,
    }


def generate_report(
    log_dirs: List[Path],
    validation_plan_path: Optional[Path] = None,
    run_id: str = "",
    commit_sha: str = "",
    comparison_base_sha: str = "",
    event_name: str = "",
    cold_report_path: Optional[Path] = None,
    output_json_path: Optional[Path] = None,
    step_summary_path: Optional[Path] = None,
) -> Dict[str, Any]:
    plan_data: Dict[str, Any] = {}
    if validation_plan_path and validation_plan_path.is_file():
        try:
            plan_data = json.loads(validation_plan_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    # Aggregate durations and cache states from all provided log dirs
    durations: Dict[str, int] = {}
    cache_states: Dict[str, str] = {}
    save_states: Dict[str, str] = {}

    for ldir in log_dirs:
        if not ldir.is_dir():
            continue
        # Check cache-mode logs
        for cml in ldir.glob("*cache-mode.log"):
            cm_dict = read_cache_mode_log(cml)
            for k, v in cm_dict.items():
                if "save" in k.lower():
                    save_states[f"{ldir.name}/{k}"] = v
                else:
                    cache_states[f"{ldir.name}/{k}"] = v

        # Check duration text files
        for df in ldir.glob("*-duration-seconds.txt"):
            dur = parse_duration_file(df)
            if dur is not None:
                step_key = df.stem.replace("-duration-seconds", "")
                durations[f"{ldir.name}/{step_key}"] = dur

    # Check test results
    executed_tests = []
    reused_tests = plan_data.get("reused_tests", [])
    skipped_validations = plan_data.get("skipped_expensive_groups", {})

    for ldir in log_dirs:
        for res_file in ldir.glob("*-results.json"):
            try:
                data = json.loads(res_file.read_text(encoding="utf-8"))
                if isinstance(data, list):
                    executed_tests.extend(data)
                elif isinstance(data, dict) and "tests" in data:
                    executed_tests.extend(data["tests"])
            except Exception:
                pass

    total_measured_time = sum(durations.values())
    baseline_full_mins = plan_data.get("cost_estimates", {}).get("baseline_full_run_minutes", 180)
    estimated_duration_mins = plan_data.get("cost_estimates", {}).get("estimated_duration_minutes", 15)
    estimated_saved_mins = plan_data.get("cost_estimates", {}).get("estimated_saved_minutes", baseline_full_mins - estimated_duration_mins)

    # Classify overall cache efficiency
    exact_hits = sum(1 for v in cache_states.values() if v.lower() in ("exact-hit", "exact_hit", "true"))
    fallback_hits = sum(1 for v in cache_states.values() if v.lower() in ("fallback-hit", "compatible_restore"))
    misses = sum(1 for v in cache_states.values() if v.lower() in ("miss", "false"))
    saves_skipped = sum(1 for v in save_states.values() if "skip" in v.lower())
    saves_created = sum(1 for v in save_states.values() if "create" in v.lower() or "saved" in v.lower())

    report: Dict[str, Any] = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "run_id": run_id or os.environ.get("GITHUB_RUN_ID", "local"),
        "commit_sha": commit_sha or plan_data.get("head_sha", os.environ.get("GITHUB_SHA", "unknown")),
        "comparison_base": comparison_base_sha or plan_data.get("base_sha", "unknown"),
        "event_name": event_name or plan_data.get("event_name", os.environ.get("GITHUB_EVENT_NAME", "unknown")),
        "is_full_validation": plan_data.get("is_full_validation", False),
        "required_build_type": plan_data.get("required_build_type", "Unknown"),
        "cache_metrics": {
            "exact_hits": exact_hits,
            "fallback_compatible_restores": fallback_hits,
            "misses": misses,
            "saves_skipped": saves_skipped,
            "saves_created": saves_created,
            "states": cache_states,
            "save_states": save_states,
        },
        "step_durations_seconds": durations,
        "total_active_seconds": total_measured_time,
        "test_metrics": {
            "reused_verified_count": len(reused_tests),
            "reused_tests": reused_tests,
            "executed_count": len(executed_tests),
            "skipped_groups_count": len(skipped_validations),
            "skipped_groups": skipped_validations,
        },
        "time_savings": {
            "is_estimated": True,
            "estimated_saved_minutes": estimated_saved_mins,
            "estimated_duration_minutes": estimated_duration_mins,
            "baseline_full_run_minutes": baseline_full_mins,
            "actual_measured_time_human": f"{total_measured_time // 60}m {total_measured_time % 60}s ({total_measured_time}s)" if total_measured_time > 0 else "N/A",
            "notes": "Estimated savings compare against a full cold baseline unless an authenticated comparison report is provided.",
        },
    }

    # If cold report is provided, perform authentic measured Cold vs Warm comparison
    comparison_data: Optional[Dict[str, Any]] = None
    if cold_report_path and cold_report_path.is_file():
        try:
            cold_data = json.loads(cold_report_path.read_text(encoding="utf-8"))
            comparison_data = compare_cold_and_warm(cold_data, report)
            report["cold_warm_comparison"] = comparison_data
        except Exception as exc:
            print(f"[generate_performance_report] Could not read cold report: {exc}", file=sys.stderr)

    if output_json_path:
        output_json_path.parent.mkdir(parents=True, exist_ok=True)
        output_json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    # Render Markdown Step Summary
    lines: List[str] = [
        "## CI Performance & Caching Summary",
        "",
        "| Metric | Value |",
        "| --- | --- |",
        f"| **Run ID** | `{report['run_id']}` |",
        f"| **Commit** | `{report['commit_sha'][:10]}` |",
        f"| **Base Commit** | `{report['comparison_base'][:10]}` |",
        f"| **Build Type** | `{report['required_build_type']}` |",
        f"| **Exact Cache Hits** | `{exact_hits}` |",
        f"| **Compatible Restores** | `{fallback_hits}` |",
        f"| **Cache Misses** | `{misses}` |",
        f"| **Cache Saves Skipped** | `{saves_skipped}` |",
        f"| **Reused Tests (Verified Pass)** | `{len(reused_tests)}` |",
        f"| **Executed Tests** | `{len(executed_tests)}` |",
        f"| **Total Active Measured Time** | `{report['time_savings']['actual_measured_time_human']}` |",
        f"| **Estimated Time Saved** | `~{estimated_saved_mins} min vs full CI (~{baseline_full_mins} min)` |",
        "",
    ]

    if comparison_data:
        c_tot = comparison_data["cold_total_seconds"]
        w_tot = comparison_data["warm_total_seconds"]
        saved = comparison_data["measured_saved_seconds"]
        pct = comparison_data["percent_reduction"]
        lines.extend([
            "### Measured Cold vs Warm Comparison",
            f"- **Cold Run Active Time**: {c_tot // 60}m {c_tot % 60}s ({c_tot}s)",
            f"- **Warm Run Active Time**: {w_tot // 60}m {w_tot % 60}s ({w_tot}s)",
            f"- **Authentic Measured Saving**: **{saved // 60}m {saved % 60}s ({saved}s, {pct}% reduction)**",
            "",
            "| Step | Cold Duration | Warm Duration | Measured Saving |",
            "| --- | --- | --- | --- |",
        ])
        for step, d in sorted(comparison_data["step_deltas"].items()):
            cs = d["cold_seconds"]
            ws = d["warm_seconds"]
            sv = d["saved_seconds"]
            lines.append(f"| `{step}` | {cs}s | {ws}s | **{sv}s** |")
        lines.append("")

    if durations:
        lines.append("### Measured Step Durations")
        lines.append("| Step | Duration |")
        lines.append("| --- | --- |")
        for step, dur in sorted(durations.items()):
            m, s = divmod(dur, 60)
            lines.append(f"| `{step}` | {m}m {s:02d}s ({dur}s) |")
        lines.append("")

    if reused_tests:
        lines.append("### Authentic Evidence Reused (Unchanged Dependencies)")
        for rt in reused_tests:
            lines.append(f"- **`{rt.get('test_id') or rt.get('suite')}`**: `REUSED_VERIFIED_PASS`")
        lines.append("")

    summary_md = "\n".join(lines)

    if step_summary_path:
        step_summary_path.parent.mkdir(parents=True, exist_ok=True)
        with step_summary_path.open("a", encoding="utf-8") as f:
            f.write(summary_md + "\n")

    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate CI Performance Report")
    parser.add_argument("--log-dir", action="append", default=[], help="Path to a log directory")
    parser.add_argument("--validation-plan", help="Path to ci-validation-plan.json")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--commit-sha", default="")
    parser.add_argument("--base-sha", default="")
    parser.add_argument("--event-name", default="")
    parser.add_argument("--cold-report", help="Path to prior cold ci-performance-report.json for comparison")
    parser.add_argument("--output-json", default="ci-performance-report.json")
    parser.add_argument("--step-summary", help="Path to GITHUB_STEP_SUMMARY")

    args = parser.parse_args()
    log_dirs = [Path(d) for d in args.log_dir]
    val_plan = Path(args.validation_plan) if args.validation_plan else None
    cold_rep = Path(args.cold_report) if args.cold_report else None
    out_json = Path(args.output_json) if args.output_json else None
    step_sum = Path(args.step_summary) if args.step_summary else None

    generate_report(
        log_dirs=log_dirs,
        validation_plan_path=val_plan,
        run_id=args.run_id,
        commit_sha=args.commit_sha,
        comparison_base_sha=args.base_sha,
        event_name=args.event_name,
        cold_report_path=cold_rep,
        output_json_path=out_json,
        step_summary_path=step_sum,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
