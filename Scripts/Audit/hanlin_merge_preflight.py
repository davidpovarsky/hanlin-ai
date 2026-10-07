#!/usr/bin/env python3
"""Inventory and trial-merge frozen Hanlin refs without changing a checkout.

Requires Python 3.10+ and Git with merge-tree --write-tree. Writes reports and
Git objects, but never checks out, stages, commits, pushes, or changes branches.
Exit 0 means the AUDIT completed, not that its trial merges were conflict-free.
"""
from __future__ import annotations
import argparse
import itertools
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULTS = {
    "skills": "03e7c70e66309068ade31fd88cc26f4741f00f53",
    "torah": "e83739594b4552bd65bfd08fae8872fd29fd57d6",
    "adapter": "05a5d3c11aa95fef9ab3d4a86318176a0be64799",
}


def git(repo: Path, *args: str, allowed: tuple[int, ...] = (0,)) -> subprocess.CompletedProcess[bytes]:
    p = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False)
    if p.returncode not in allowed:
        raise RuntimeError(f"git {args[0]} failed (exit {p.returncode}): "
                           + p.stderr.decode("utf-8", errors="replace")[-2000:])
    return p


def text(repo: Path, *args: str, allowed: tuple[int, ...] = (0,)) -> str:
    return git(repo, *args, allowed=allowed).stdout.decode("utf-8", errors="strict").strip()


def resolve(repo: Path, ref: str) -> str:
    if not ref or ref.startswith("-") or any(c in ref for c in "\r\n\x00"):
        raise ValueError("Unsafe or empty ref")
    return text(repo, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}")


def entries(repo: Path, sha: str) -> dict[str, dict[str, str]]:
    result = {}
    raw = git(repo, "ls-tree", "-r", "-z", "--full-tree", sha).stdout
    for record in raw.split(b"\x00"):
        if not record:
            continue
        metadata, path = record.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split()
        result[path.decode("utf-8", errors="surrogateescape")] = {
            "mode": mode, "type": kind, "oid": oid
        }
    return result


def changed(base: dict, head: dict) -> set[str]:
    return {p for p in set(base) | set(head) if base.get(p) != head.get(p)}


def dump(path: Path, obj: Any) -> None:
    path.write_text(json.dumps(obj, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


def collect(repo: Path, out: Path, refs: dict[str, str], candidate: str | None) -> dict:
    repo = repo.resolve()
    if text(repo, "rev-parse", "--is-shallow-repository") == "true":
        raise RuntimeError("Use a complete-history isolated clone; shallow history is not merge evidence.")
    pins = {role: resolve(repo, ref) for role, ref in refs.items()}
    cand = resolve(repo, candidate) if candidate else None
    out.mkdir(parents=True, exist_ok=False)
    snapshot = {
        "auditVersion": 1,
        "createdAtUTC": datetime.now(timezone.utc).isoformat(),
        "gitVersion": text(repo, "--version"),
        "sourceInputs": refs,
        "sourcePins": pins,
        "candidate": cand,
        "auditIsNotBuildOrRuntimeVerification": True,
        "pinsDifferFromDocument": {r: {"audited": DEFAULTS[r], "actual": s}
                                  for r, s in pins.items() if s != DEFAULTS[r]},
        "commits": {r: text(repo, "show", "-s", "--format=%H%n%cI%n%s", s)
                    for r, s in pins.items()},
    }
    dump(out / "source-pins.json", snapshot)
    trees = {r: entries(repo, s) for r, s in pins.items()}
    candidate_tree = entries(repo, cand) if cand else None
    pairs = []
    errors = []
    for a, b in itertools.combinations(pins, 2):
        pair_name = a + "--" + b
        bases = text(repo, "merge-base", "--all", pins[a], pins[b]).splitlines()
        counts = text(repo, "rev-list", "--left-right", "--count", pins[a] + "..." + pins[b]).split()
        info = {"left": a, "right": b, "mergeBases": bases,
                "leftOnlyCommits": int(counts[0]), "rightOnlyCommits": int(counts[1])}
        if len(bases) == 1:
            bt = entries(repo, bases[0])
            ca, cb = changed(bt, trees[a]), changed(bt, trees[b])
            overlap = sorted(ca & cb)
            rows = [{"path": p, "base": bt.get(p), a: trees[a].get(p),
                     b: trees[b].get(p), "sameFinalEntry": trees[a].get(p) == trees[b].get(p)}
                    for p in overlap]
            info.update({"leftChangedPaths": len(ca), "rightChangedPaths": len(cb),
                         "overlapPaths": len(overlap),
                         "sameFinalOverlapPaths": sum(x["sameFinalEntry"] for x in rows),
                         "differentFinalOverlapPaths": sum(not x["sameFinalEntry"] for x in rows)})
            dump(out / (pair_name + ".overlap.json"), rows)
            for role in (a, b):
                prefix = pair_name + "." + role
                for suffix, options in (("name-status.txt", ["--name-status"]),
                                        ("patch.diff", ["--binary", "--full-index"])):
                    content = git(repo, "diff", "--find-renames", *options, bases[0], pins[role], "--").stdout
                    (out / (prefix + "." + suffix)).write_bytes(content)
        else:
            info["inventoryWarning"] = "Multiple merge bases: do not force one base; inspect actual recursive merge."
        trial = git(repo, "merge-tree", "--write-tree", "--name-only", "--messages",
                    pins[a], pins[b], allowed=tuple(range(256)))
        (out / (pair_name + ".merge-tree.stdout.txt")).write_bytes(trial.stdout)
        (out / (pair_name + ".merge-tree.stderr.txt")).write_bytes(trial.stderr)
        info["mergeTreeExitCode"] = trial.returncode
        info["mergeTreeStatus"] = {0: "CLEAN_TEXTUAL_MERGE", 1: "CONFLICTS"}.get(trial.returncode, "OPERATIONAL_ERROR")
        if trial.returncode not in (0, 1):
            errors.append(pair_name + ": merge-tree failed; this is not a merge result")
        pairs.append(info)

    common = text(repo, "merge-base", "--all", "--octopus", *pins.values()).splitlines()
    union_rows = []
    if len(common) == 1:
        bt = entries(repo, common[0])
        touched = set().union(*(changed(bt, t) for t in trees.values()))
        for p in sorted(touched):
            source_changes = {r: t.get(p) for r, t in trees.items() if t.get(p) != bt.get(p)}
            unique_changes = {json.dumps(e, sort_keys=True) for e in source_changes.values()}
            unambiguous = len(unique_changes) == 1
            expected = next(iter(source_changes.values())) if unambiguous else None
            row = {"path": p, "base": bt.get(p), "changedBy": source_changes,
                    "classification": "ONE_UNAMBIGUOUS_SOURCE_RESULT" if unambiguous else "SEMANTIC_REVIEW_REQUIRED"}
            if unambiguous:
                row["expectedEntry"] = expected
            if cand:
                actual = candidate_tree.get(p)
                row["candidateEntry"] = actual
                if unambiguous:
                    row["matchesExpected"] = actual == expected
                    row["needsExplicitResolutionRationale"] = actual != expected
                else:
                    row["needsExplicitResolutionRationale"] = True
            union_rows.append(row)
        dump(out / "union-source-inventory.json", union_rows)
    else:
        errors.append("No unique common base for union inventory; extend the audit rather than guessing.")

    ancestry = {}
    if cand:
        for role, sha in pins.items():
            result = git(repo, "merge-base", "--is-ancestor", sha, cand, allowed=(0, 1))
            ancestry[role] = result.returncode == 0
        if not all(ancestry.values()):
            errors.append("At least one frozen source tip is not an ancestor of candidate.")
    result = {"sourcePins": pins, "candidate": cand, "commonBases": common,
              "pairs": pairs, "candidateContainsAllSourceTips": ancestry,
              "unionChangedPaths": len(union_rows),
              "unambiguousCandidateDeviations": sum(x.get("matchesExpected") is False for x in union_rows),
              "operationalErrors": errors,
              "auditExit0DoesNotMeanMergeOrBuildPassed": True}
    dump(out / "audit-summary.json", result)
    return result


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True, help="New report directory; never overwritten")
    for role, sha in DEFAULTS.items():
        p.add_argument("--" + role, default=sha)
    p.add_argument("--candidate", help="Optional integrated commit to check for ancestry and preservation")
    args = p.parse_args()
    try:
        result = collect(args.repo, args.out, {r: getattr(args, r) for r in DEFAULTS}, args.candidate)
        print(json.dumps(result, ensure_ascii=True, indent=2))
        return 2 if result["operationalErrors"] else 0
    except (OSError, RuntimeError, ValueError, UnicodeError) as exc:
        print("AUDIT FAILED: " + str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
