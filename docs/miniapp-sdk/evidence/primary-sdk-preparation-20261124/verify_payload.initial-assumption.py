#!/usr/bin/env python3
"""Bounded read-only verification of an existing prepared-source payload.

This script reads authenticated transferred files and Git objects. It writes only
its two evidence JSON outputs; it does not apply, generate, build, or test sources.
"""
import datetime
import hashlib
import json
import pathlib
import subprocess

REPO = pathlib.Path("/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124")
SNAPSHOT = pathlib.Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt5")
OUTPUT = REPO / "docs/miniapp-sdk/evidence/primary-sdk-preparation-20261124"
EXECUTION = "340018ddc9ea2395ffabedbf179369b5bdb791af"
EVIDENCE_BASE = "b3a7c56fa6b691503fff04a0ddd5a1eeb6f736be"
EXPECTED_LEDGER = "b4381014062cca249740e1ff83c6d78d07680c2b27b51ac0569f2ea96e1a20ff"
PIN_PATH = "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

def sha(data):
    return hashlib.sha256(data).hexdigest()

def save(name, value):
    p = OUTPUT / name
    p.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    return {"path": str(p), "bytes": p.stat().st_size, "sha256": sha(p.read_bytes())}

def git_blobs(requests):
    command = ["git", "cat-file", "--batch"]
    proc = subprocess.run(command, cwd=REPO, input=("\n".join(requests)+"\n").encode(),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    out, offset, result = proc.stdout, 0, {}
    for request in requests:
        end = out.index(b"\n", offset)
        header = out[offset:end].decode()
        fields = header.split()
        assert len(fields) == 3 and fields[1] == "blob", (request, header)
        size = int(fields[2])
        start = end + 1
        body = out[start:start+size]
        assert out[start+size:start+size+1] == b"\n"
        result[request] = {"gitBlob": fields[0], "bytes": body}
        offset = start + size + 1
    assert offset == len(out)
    return result

def category(path):
    if "/NativeScriptSharedRuntime/" in path:
        return "prepared-nativescript-shared-runtime"
    if path.endswith(".hanlinExpo"):
        return "generated-expo-fixture-archive"
    if path == PIN_PATH:
        return "xcode-swift-package-resolution"
    if path.endswith("/ExpoWidgets.bundle/original-runtime-receipt.json"):
        return "original-expo-widgets-runtime-receipt"
    if path.startswith("docs/miniapp-sdk/"):
        return "generated-sdk-provenance-document"
    return "UNCLASSIFIED"

def main():
    ledger_path = SNAPSHOT / "tracked-delta.json"
    ledger_bytes = ledger_path.read_bytes()
    assert sha(ledger_bytes) == EXPECTED_LEDGER
    ledger = json.loads(ledger_bytes)
    assert len(ledger) == 188
    assert len({r["path"] for r in ledger}) == 188
    requests = [commit + ":" + r["path"] for commit in (EXECUTION, EVIDENCE_BASE) for r in ledger]
    blobs = git_blobs(requests)
    rows = []
    failures = []
    categories = {}
    for r in ledger:
        path = r["path"]
        assert r["kind"] == "file"
        source = (SNAPSHOT / r["contentFrom"]).resolve()
        assert source.is_relative_to(SNAPSHOT.resolve())
        data = source.read_bytes()
        old = blobs[EXECUTION + ":" + path]
        base = blobs[EVIDENCE_BASE + ":" + path]
        result = {
            "path": path,
            "category": category(path),
            "payloadRelativePath": r["contentFrom"],
            "payloadAbsolutePath": str(source),
            "beforeSHA256": sha(old["bytes"]),
            "beforeBytes": len(old["bytes"]),
            "beforeGitBlob": old["gitBlob"],
            "afterSHA256": sha(data),
            "afterBytes": len(data),
            "ledgerBeforeSHA256": r["headSHA256"],
            "ledgerAfterSHA256": r["sha256"],
            "ledgerBytes": r["bytes"],
            "executionBeforeMatchesLedger": sha(old["bytes"]) == r["headSHA256"],
            "afterMatchesLedger": sha(data) == r["sha256"] and len(data) == r["bytes"],
            "evidenceBaseBeforeMatchesExecution": base["bytes"] == old["bytes"],
            "changedFromExecution": data != old["bytes"]
        }
        rows.append(result)
        categories[result["category"]] = categories.get(result["category"], 0) + 1
        for field in ("executionBeforeMatchesLedger", "afterMatchesLedger",
                      "evidenceBaseBeforeMatchesExecution", "changedFromExecution"):
            if not result[field]:
                failures.append({"path": path, "check": field})
    protected_exact = {
        "AGENTS.md", "PROJECT_AGENT_GUIDANCE.md",
        "Scripts/Expo/prepare-ios-dependencies.mjs",
        "Scripts/CI/stage_modular_headers.py",
        "Scripts/Runtime/prepare-runtime-core.sh",
        "Scripts/Runtime/prepare-runtime-host.sh",
        "Scripts/NativeScript/prepare-ios-dependencies.mjs",
        "Scripts/NativeScript/build-host-services.mjs",
        "Scripts/SDK/update_project.py",
        "AI_HLY.xcodeproj/project.pbxproj"
    }
    protected_hits = [r["path"] for r in rows if r["path"] in protected_exact]
    canonical = [{"path": r["path"], "beforeSHA256": r["beforeSHA256"],
                  "afterSHA256": r["afterSHA256"], "afterBytes": r["afterBytes"],
                  "payloadRelativePath": r["payloadRelativePath"]} for r in rows]
    canonical_bytes = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    verification = {
        "schemaVersion": 1,
        "observedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "status": "VERIFIED" if not failures and not protected_hits else "MISMATCH",
        "scope": "Existing transferred payload bytes and immutable Git objects only; no source application, preparation, build, compiler, or test execution.",
        "executionSource": EXECUTION,
        "compatibleEvidenceBase": EVIDENCE_BASE,
        "expectedApplyBase": EXECUTION,
        "applyRule": "Require each destination's SHA256 to equal this row's beforeSHA256 before replacing it with the existing payload file. A newer base requires this same per-file precondition; do not overwrite unrelated source edits.",
        "snapshotRoot": str(SNAPSHOT),
        "existingPayloadRoots": [str(SNAPSHOT / "tracked-delta"), str(SNAPSHOT / "files")],
        "ledger": {"path": str(ledger_path), "bytes": len(ledger_bytes), "sha256": sha(ledger_bytes)},
        "canonicalPayloadBinding": {
            "algorithm": "SHA256 over UTF-8 JSON of rows in ledger order with keys sorted, separators comma/colon, and fields path,beforeSHA256,afterSHA256,afterBytes,payloadRelativePath",
            "sha256": sha(canonical_bytes)
        },
        "rowCount": len(rows),
        "totalPayloadBytes": sum(r["afterBytes"] for r in rows),
        "categories": categories,
        "allExecutionBeforeHashesMatch": all(r["executionBeforeMatchesLedger"] for r in rows),
        "allPayloadAfterHashesAndSizesMatch": all(r["afterMatchesLedger"] for r in rows),
        "allEvidenceBaseBeforeBytesMatch": all(r["evidenceBaseBeforeMatchesExecution"] for r in rows),
        "allRowsActuallyChangeBytes": all(r["changedFromExecution"] for r in rows),
        "protectedExactPathsChecked": sorted(protected_exact),
        "protectedPathOverlap": protected_hits,
        "unclassifiedPaths": [r["path"] for r in rows if r["category"] == "UNCLASSIFIED"],
        "failures": failures,
        "files": rows
    }

    original = blobs[EXECUTION + ":" + PIN_PATH]["bytes"]
    pin_row = next(r for r in ledger if r["path"] == PIN_PATH)
    prepared = (SNAPSHOT / pin_row["contentFrom"]).read_bytes()
    before, after = json.loads(original), json.loads(prepared)
    bp = {p["identity"]: p for p in before["pins"]}
    ap = {p["identity"]: p for p in after["pins"]}
    assert len(bp) == len(before["pins"]) and len(ap) == len(after["pins"])
    pin_rows = []
    for identity in sorted(bp.keys() | ap.keys()):
        b, a = bp.get(identity), ap.get(identity)
        pin_rows.append({
            "identity": identity,
            "before": b, "after": a,
            "status": "added" if b is None else "removed" if a is None else "unchanged" if b == a else "changed",
            "revisionChanged": b is not None and a is not None and b.get("state", {}).get("revision") != a.get("state", {}).get("revision"),
            "versionChanged": b is not None and a is not None and b.get("state", {}).get("version") != a.get("state", {}).get("version"),
            "locationChanged": b is not None and a is not None and b.get("location") != a.get("location"),
            "kindChanged": b is not None and a is not None and b.get("kind") != a.get("kind")
        })
    comparison = {
        "schemaVersion": 1, "path": PIN_PATH,
        "before": {"source": EXECUTION, "sha256": sha(original), "bytes": len(original),
                   "version": before.get("version"), "originHash": before.get("originHash"),
                   "otherTopLevelFields": {k:v for k,v in before.items() if k not in ("pins","version","originHash")}},
        "after": {"source": str(SNAPSHOT / pin_row["contentFrom"]), "sha256": sha(prepared), "bytes": len(prepared),
                  "version": after.get("version"), "originHash": after.get("originHash"),
                  "otherTopLevelFields": {k:v for k,v in after.items() if k not in ("pins","version","originHash")}},
        "pinCounts": {"before": len(bp), "after": len(ap), "unchanged": sum(r["status"]=="unchanged" for r in pin_rows),
                      "changed": sum(r["status"]=="changed" for r in pin_rows),
                      "added": sum(r["status"]=="added" for r in pin_rows),
                      "removed": sum(r["status"]=="removed" for r in pin_rows)},
        "revisionChanges": [r["identity"] for r in pin_rows if r["revisionChanged"]],
        "versionChanges": [r["identity"] for r in pin_rows if r["versionChanged"]],
        "locationChanges": [r["identity"] for r in pin_rows if r["locationChanged"]],
        "kindChanges": [r["identity"] for r in pin_rows if r["kindChanged"]],
        "pins": pin_rows,
        "boundary": "This proves exact recorded resolution differences, not a package-resolution rerun or downstream build result."
    }
    out1 = save("payload-verification.json", verification)
    out2 = save("package-resolved-comparison.json", comparison)
    print(json.dumps({"payload": {"status": verification["status"], "rowCount": len(rows),
          "totalPayloadBytes": verification["totalPayloadBytes"], "categories": categories,
          "canonicalPayloadBinding": verification["canonicalPayloadBinding"]["sha256"],
          "protectedPathOverlap": protected_hits, "failures": failures},
          "pins": {k: comparison[k] for k in ("pinCounts","revisionChanges","versionChanges","locationChanges","kindChanges")},
          "outputs": [out1,out2]}, indent=2))
    assert not failures and not protected_hits and not verification["unclassifiedPaths"]

if __name__ == "__main__":
    main()
