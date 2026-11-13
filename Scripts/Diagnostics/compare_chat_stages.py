"""Compare readable CHATUX-13 snapshots locally; never execute tools or upload logs.

The result contains hashes/offsets, not conversation text. Transport snapshots
are diagnostic SSE reconstructions. A match does not prove UI pixel parity or
attribute the old Build98201 issue without a captured reproduction.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def fingerprint(text: str) -> dict:
    encoded = text.encode("utf-8")
    return {"utf8Bytes": len(encoded), "unicodeScalars": len(text),
            "sha256": hashlib.sha256(encoded).hexdigest(), "replacementCharacters": text.count("\ufffd")}


def compare_text(source: str, output: str) -> dict:
    offset = next((index for index, (a, b) in enumerate(zip(source, output)) if a != b),
                  min(len(source), len(output)))
    return {"status": "MATCH" if source == output else "DIVERGED",
            "firstDifferentScalar": None if source == output else offset,
            "firstDifferentUTF8Byte": None if source == output else len(source[:offset].encode("utf-8")),
            "source": fingerprint(source), "output": fingerprint(output)}


def compare_session(manifest_path: Path) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    root = manifest_path.parent.resolve()

    def companion(key: str) -> Path:
        name = manifest[key]
        if not isinstance(name, str) or Path(name).name != name or "/" in name or "\\" in name:
            raise ValueError("Manifest companion must be a basename in this Diagnostics directory")
        path = (root / name).resolve()
        if path.parent != root:
            raise ValueError("Manifest companion escapes the Diagnostics directory")
        return path

    if manifest.get("truncated") or manifest.get("captureError"):
        return {"status": "INCOMPLETE_CAPTURE", "runID": manifest.get("runID"),
                "droppedByteCount": manifest.get("droppedByteCount"), "captureError": manifest.get("captureError")}
    snapshots = json.loads(companion("snapshotsFile").read_text(encoding="utf-8"))
    attempts: dict[str, str] = {}
    for line in companion("eventsFile").read_text(encoding="utf-8").splitlines():
        event = json.loads(line)
        if event.get("stage") == "transport.request" and event.get("attemptID") and event.get("roundID"):
            attempts[event["attemptID"]] = event["roundID"]
    rounds = []
    for attempt, round_id in attempts.items():
        if list(attempts.values()).count(round_id) > 1:
            rounds.append({"attemptID": attempt, "roundID": round_id, "status": "AMBIGUOUS_RETRY_CORRELATION"})
            continue
        source_key = f"{attempt}.response.choices.0.delta.content"
        # Other provider formats require a declared mapping; never guess a field
        # because its text happens to resemble the final answer.
        stages = [source_key, f"{round_id}.SwiftAISDK.content", f"{round_id}.StreamData.content"]
        missing = [name for name in stages if name not in snapshots]
        if missing:
            rounds.append({"attemptID": attempt, "roundID": round_id, "status": "MISSING_STAGE",
                           "missing": missing})
            continue
        comparisons = [dict(fromStage=a, toStage=b, **compare_text(snapshots[a], snapshots[b]))
                       for a, b in zip(stages, stages[1:])]
        first = next((item for item in comparisons if item["status"] == "DIVERGED"), None)
        rounds.append({"attemptID": attempt, "roundID": round_id,
                       "status": "DIVERGED" if first else "MATCH", "firstDivergence": first,
                       "comparisons": comparisons})
    return {"schemaVersion": 1, "runID": manifest.get("runID"), "rounds": rounds,
            "status": "NO_CORRELATED_ATTEMPTS" if not rounds else
                      "DIVERGED" if any(item["status"] == "DIVERGED" for item in rounds) else
                      "INCOMPLETE_CAPTURE" if any(item["status"] != "MATCH" for item in rounds) else "MATCH",
            "uiAcceptance": "NOT_VERIFIED_BY_SOURCE_SNAPSHOTS",
            "redactedComparison": True,
            "retryAcceptance": "Compare retries separately; no side effects are replayed by this tool"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    result = compare_session(args.manifest)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "MATCH" else 1


if __name__ == "__main__":
    raise SystemExit(main())
