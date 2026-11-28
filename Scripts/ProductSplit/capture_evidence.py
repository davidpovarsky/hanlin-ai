"""Capture bounded, read-only lane snapshots and the canonical 26-choice summary.

Only docs/product-split output is written. Other worktrees are never modified.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/product-split"
BASELINE = "dd700c03e9fe9d22e95a031d4684275512ee6e6f"


def git(directory, *args):
    return subprocess.check_output(["git", "-C", str(directory), *args], text=True, encoding="utf-8").strip()


def capture():
    inventory = json.loads((OUTPUT / "feature-delta-278.json").read_text(encoding="utf-8"))
    ids = {r["id"] for r in inventory["rows"]}
    summary = [
        ("KEEP", "split", ["NAV-23", "NAV-24"], "Retain native compact/wide behavior; two app targets do not require Chat layout replacement"),
        ("KEEP", "tabs", ["NAV-01"], "Conflict with proposed Chat/Library IA and separate MiniApps app; J decision pending; no tab rewrite"),
        ("KEEP", "groups", ["NAV-04", "RUN-05", "RUN-14"], "Preserve conversation/message grouping semantics; full original choice wording needed for exact visual mapping"),
        ("KEEP", "title", ["NAV-17", "RESULT-02"], "Retain title/model identity and rename behavior; preserve approved host"),
        ("KEEP", "apps", ["MINI-01", "MINI-03", "MINI-16", "MINI-17"], "Catalog owner becomes MiniApps; AI tools and inline results remain available; J decides launch affordance"),
        ("KEEP", "collapse", ["RESULT-04", "RESULT-06"], "Retain reasoning/tool details and their persisted visibility semantics"),
        ("KEEP", "activityrow", ["RESULT-05", "RESULT-27", "RESULT-28"], "Retain existing activity semantics; no separate speculative activity engine"),
        ("KEEP", "inspector", ["RESULT-29"], "Retain detail/inspector and exact tool-result identity"),
        ("KEEP", "evidence", ["RESULT-11", "RESULT-30", "RESULT-31"], "Retain original Evidence system and inline source integration; no new duplicate source store"),
        ("KEEP", "shimmer", ["RESULT-28", "RESULT-38"], "Retain status and Reduce Motion behavior, subject to current UI owner"),
        ("KEEP", "embedded", ["RESULT-32", "RESULT-33", "RESULT-36", "MINI-16"], "AI retains embedded results and A2UI; never transfer all UI output to companion"),
        ("KEEP", "expansion", ["RESULT-29", "RESULT-34", "RESULT-37"], "Inline expansion stays AI; full app launches use authenticated foreground continuation"),
        ("KEEP", "modelmenu", ["INPUT-09", "INPUT-10", "INPUT-11"], "Preserve current model picker and mention paths; do not force a permanent model bar against Morph design"),
        ("KEEP", "attachments", ["ATT-01", "INPUT-05", "INPUT-06", "INPUT-15"], "Preserve live attachments/drafts/paste and attachments-only send through Composer owner"),
        ("RESTORE_TRIAL", "rows", ["NAV-04", "RESULT-01"], "Current literal restoration is authoritative; no split-owned row redesign"),
        ("RESTORE_TRIAL", "bubblecolor", ["RESULT-01"], "Keep current approved chat visual identity; no change in split tranche"),
        ("RESTORE_TRIAL", "corners", ["RESULT-01"], "Keep current chat geometry; full original specification needed for detailed visual parity"),
        ("RESTORE_TRIAL", "bubblewidth", ["RESULT-01", "RESULT-38"], "Preserve current width/accessibility/platform behavior; no split UI edit"),
        ("RESTORE_TRIAL", "actions", ["RESULT-07", "RESULT-10", "RESULT-35"], "Preserve actions and precise origin identity; only cross-app destination changes later"),
        ("RESTORE_TRIAL", "transcript presentation", ["RUN-14", "RESULT-27"], "Retain typed transcript/replay order and current presentation; no schema migration"),
        ("RESTORE_TRIAL", "scroll", ["NAV-12", "RESULT-38"], "Preserve search-to-message, follow/stop and platform sizing; device acceptance remains open"),
        ("RESTORE_TRIAL", "resultframe", ["RESULT-33", "RESULT-34"], "Retain bounded inline result frames; full companion is distinct foreground presentation"),
        ("RESTORE_TRIAL", "glass design language", ["INPUT-01", "INPUT-03"], "Authenticated Morph reference W1-002 belongs to Maya; split does not replace or infer active-tools styling"),
        ("RESTORE_TRIAL", "inputwidth", ["INPUT-01", "INPUT-03"], "Maya owns reference measurement/overflow and approved host seam; no hand-coded competing composer"),
        ("RESTORE_TRIAL", "floating", ["INPUT-01", "INPUT-03", "INPUT-15"], "Keep authentic outer bubble/page transition/lifecycle under Composer owner"),
        ("OPEN", "hiding", ["RESULT-04", "RESULT-06", "RESULT-27", "RESULT-32"], "Keep all content accessible with no duplicate presentation; detailed hiding rule remains J/owner acceptance"),
    ]
    decisions = []
    for index, (choice, name, features, resolution) in enumerate(summary, 1):
        if not set(features).issubset(ids):
            raise ValueError(f"UI choice {name} refers to missing IDs")
        decisions.append({"id": f"LEGACY-UI-{index:02d}", "historical_choice": choice,
                          "canonical_summary_name": name, "feature_ids": features,
                          "resolution": resolution, "status": "MAPPED_ACCEPTANCE_OPEN"})
    (OUTPUT / "legacy-ui-decisions.json").write_text(json.dumps({
        "source": "Asana parent 1219605220179926 notes, read 2026-11-15; canonical 14 KEEP + 11 RESTORE/TRIAL + 1 OPEN summary",
        "full_original_prompt": "Hanlin_Classic_Native_UI_Inline_Sources_Composer_MASTER_PROMPT_2026-10-12.md not found in the worktree; exact full wording/visual acceptance not claimed",
        "current_overrides": ["2026-11-15 split approved; no broad Chat redesign", "W1-002 authenticated Morph source and Maya's narrow ChatViewBottom lease", "A2UI official renderer lane retains inline result ownership"],
        "count": len(decisions), "decisions": decisions}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    lanes = []
    for name, directory, patterns in [
        ("Runtime", ROOT.parent / "hanlin-agent-skills-embedded-results", ["docs/miniapp-sdk/HANDOFF_2026-11-15.md"]),
        ("A2UI", ROOT.parent / "hanlin-a2ui-wave1-20261115", ["AI_HLY/Downstream/ChatPresentation/A2UI/*.swift", "docs/a2ui/*.md"]),
        ("Composer", ROOT.parent / "hanlin-composer-wave1-20261115", ["AI_HLY/Downstream/ChatInput/HanlinMorphComposer.swift", "AI_HLY/Views/Components/ChatViewBottom.swift", "docs/composer/*.md"]),
    ]:
        files = []
        for pattern in patterns:
            for path in sorted(directory.glob(pattern)):
                if path.is_file():
                    data = path.read_bytes()
                    files.append({"path": path.relative_to(directory).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        head = git(directory, "rev-parse", "HEAD")
        lanes.append({"lane": name, "worktree": str(directory), "head": head,
                      "branch": git(directory, "branch", "--show-current"),
                      "dirty_paths": git(directory, "status", "--short").splitlines(),
                      "committed_delta_from_split_baseline": git(ROOT, "diff", "--name-status", BASELINE, head).splitlines(),
                      "observed_files": files, "claim": "Point-in-time source snapshot only; no merge, copied source or reused test PASS"})
    (OUTPUT / "lane-source-snapshots.json").write_text(json.dumps({"baseline": BASELINE, "snapshots": lanes}, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"legacy_decisions": len(decisions), "lanes_snapshotted": len(lanes)}))


if __name__ == "__main__":
    capture()
