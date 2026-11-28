"""Reproducible, conservative 278-ID source inventory and strict coverage validator.

Path/line anchors identify current owning components, not proof of feature behavior.
No row is marked PASS by discovering a file. Future verification must supply evidence.
"""
from collections import Counter
from pathlib import Path
import argparse
from functools import lru_cache
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HISTORY = "e792b0b5fab6a66ea8cbdaa9626def509744e33f"
BASELINE = "dd700c03e9fe9d22e95a031d4684275512ee6e6f"
SOURCE = "docs/product/Hanlin_Feature_Decision_Matrix_2026-10-11.md"
DIGEST = "7252f34685839bd179314e8ce7b2266ea035eb73818ef378e9f28158709ce19e"
OUTPUT = ROOT / "docs/product-split"
ROW = re.compile(r"^\| `([A-Z]+-\d+)` \| `([A-Z_]+)` \| (.*?) \| (.*?) \|$", re.M)
ANCHORS = {
    "NAV": ["AI_HLY/ListView.swift", "AI_HLY/Model/ChatRecords.swift"],
    "INPUT": ["AI_HLY/Views/Components/ChatViewBottom.swift", "AI_HLY/Downstream/ChatInput/NativeMultilineTextEditor.swift"],
    "ATT": ["AI_HLY/Views/Components/ChatandFile.swift", "AI_HLY/Views/Components/DocumentPicker.swift"],
    "MODEL": ["AI_HLY/Downstream/ChatInput/HanlinModelPickerPopover.swift", "AI_HLY/SettingsView.swift"],
    "RUN": ["AI_HLY/Services/ChatServices/APIManager.swift", "AI_HLY/Downstream/AgentActivity/AgentRunLifecycleCoordinator.swift"],
    "RESULT": ["AI_HLY/Views/Components/ChatViewComponents.swift", "AI_HLY/Downstream/ChatPresentation/ChatPresentationBridge.swift"],
    "CANVAS": ["AI_HLY/Services/ChatServices/CanvasServices.swift"],
    "MEDIA": ["AI_HLY/VisionView.swift", "AI_HLY/Services/VisionServices/VisionAPI.swift"],
    "LIB": ["AI_HLY/KnowledgeListView.swift", "AI_HLY/Model/MemoryArchive.swift", "AI_HLY/Model/PromptRepo.swift"],
    "AGENT": ["AI_HLY/Downstream/CanonicalTools/HanlinCanonicalToolAuthority.swift", "AI_HLY/Downstream/AgentSkills/SkillStore.swift", "AI_HLY/Downstream/MCP/ToolIntegration/MCPToolBridge.swift"],
    "RUNTIME": ["AI_HLY/Downstream/HostServices/Core/HanlinHostServicesBroker.swift", "AI_HLY/Downstream/RuntimeCore/UI/RuntimeCenterView.swift"],
    "MINI": ["AI_HLY/NativeAppPlatform/AppsHub/NativeAppsHubView.swift", "AI_HLY/Downstream/MiniApps/HanlinMiniAppHost.swift", "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift"],
    "SYS": ["AI_HLY/AI_HLY.swift", "AI_HLY/SettingsView.swift", "AI_HLY/Model/ChatRecords.swift"],
}
MIGRATION = {
    "NAV": "AI transcript, UUID relationships, drafts, pin/order/search state: preserve existing SwiftData/CloudKit store in place",
    "INPUT": "AI per-chat drafts, attachments, mentions, pending first turn and composer session: no store relocation",
    "ATT": "AI attachment bytes and security-scoped bookmarks: retain originals; reauthorize access in destination sandbox",
    "MODEL": "AI provider/model configuration, credentials and local model inventory: no Keychain access-group changes",
    "RUN": "AI tool/session/run generations, cancellation and result correlation: retain identities and replay order",
    "RESULT": "AI typed transcript/results/citations and legacy embedded payloads: preserve original schemas",
    "CANVAS": "AI Canvas document/version history: preserve IDs and byte content in existing store",
    "MEDIA": "AI media/voice preferences and assets: no assumption of transferred camera/microphone/system permission",
    "LIB": "AI knowledge/chunks/memory/prompts: preserve relationships and CloudKit ownership",
    "AGENT": "AI Skills/MCP/provider credentials and canonical tool identities: retain one authority and registrations",
    "RUNTIME": "Shared runtime policy and scoped app/package/agent files/SQLite: no engine copy or elevated grants",
    "MINI": "MiniApps package/install/app IDs, generations, hidden state, data and grants: versioned snapshot/copy pending AppGroup authority decision",
    "SYS": "Per-extension ownership, CloudKit, Keychain, AppGroups, notifications/intents/translation: entitlement and physical-device gate",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def historical():
    data = git("show", f"{HISTORY}:{SOURCE}")
    if hashlib.sha256(data).hexdigest() != DIGEST:
        raise ValueError("historical blob digest mismatch")
    rows = ROW.findall(data.decode("utf-8"))
    ids = [r[0] for r in rows]
    if len(ids) != 278 or len(set(ids)) != 278:
        raise ValueError("historical denominator must be exactly 278 unique IDs")
    return data, rows


@lru_cache(maxsize=None)
def anchor(path, level, revision=BASELINE):
    data = git("show", f"{revision}:{path}")
    lines = data.decode("utf-8-sig").splitlines()
    line = next((i for i, value in enumerate(lines, 1)
                 if re.search(r"\b(struct|class|actor|enum|func)\b", value) and not value.lstrip().startswith("//")), 1)
    return {"path": path, "line": line, "sha256": hashlib.sha256(data).hexdigest(), "revision": revision, "level": level}


def generate(target_revision=BASELINE):
    if not re.fullmatch(r"[0-9a-f]{40}", target_revision):
        raise ValueError("target revision must be an exact source commit SHA")
    blob, original = historical()
    paths = git("ls-tree", "-r", "--name-only", target_revision).decode().splitlines()
    by_name = {}
    for path in paths:
        by_name.setdefault(Path(path).name, []).append(path)
    rows = []
    for feature_id, decision, feature, note in original:
        group = feature_id.split("-")[0]
        explicit = []
        for name in re.findall(r"`([^`/]+\.swift)`", feature):
            explicit.extend(by_name.get(name, []))
        evidence = [anchor(p, "HISTORICAL_FILENAME_RESOLVED", target_revision) for p in dict.fromkeys(explicit)]
        evidence += [anchor(p, "COMPONENT_ANCHOR_ONLY", target_revision) for p in ANCHORS[group] if p not in explicit]
        owner = "SHARED" if decision == "SHARED" else "MINIAPPS" if decision == "MINI" else "AI"
        status = "BLOCKED" if decision in {"FIX_FIRST", "RETIRE"} else "NOT_RUN"
        rows.append({"id": feature_id, "historical_decision": decision, "historical_feature": feature,
                     "historical_redesign_note": note, "owner_target": owner,
                     "visibility": decision, "retention": "PRESERVE_CAPABILITY_AND_DATA_PENDING_ACCEPTANCE",
                     "source_evidence": evidence, "availability": "SOURCE_COMPONENT_IDENTIFIED_BEHAVIOR_UNVERIFIED",
                     "migration": MIGRATION[group], "permissions": "Reevaluate existing identity/package lifecycle/system authority; never trust URL or manufacture grants",
                     "accessibility": "Verify iPhone/iPad, RTL/LTR, Dynamic Type, VoiceOver, keyboard/pointer, Reduce Motion where applicable",
                     "test_obligation": f"PARITY-{feature_id}", "acceptance_status": status,
                     "execution_evidence": [], "unresolved_decision": "Feature-specific semantic/OS/device parity not verified; component anchors are not behavior proof" +
                     ("; J must approve new IA/visual placement" if decision in {"REMOVE_UI", "VISIBLE", "MINI", "RETIRE"} else "")})
    OUTPUT.mkdir(exist_ok=True)
    (OUTPUT / "historical-278.md").write_bytes(blob)
    result = {"schema_version": 1, "historical_revision": HISTORY, "historical_blob_sha256": DIGEST,
              "baseline": BASELINE, "historical_count": 278, "rows": rows,
              "target_revision": target_revision,
              "target_project": {"path": "AI_HLY.xcodeproj/project.pbxproj", "revision": target_revision,
                  "sha256": hashlib.sha256(git("show", f"{target_revision}:AI_HLY.xcodeproj/project.pbxproj")).hexdigest()},
              "new_capabilities": [
                  {"id": "SPLIT-FOREGROUND-V1", "provenance": "W1-003", "status": "SOURCE_IMPLEMENTED_PORTABLE_TESTS_SEPARATE", "affects": ["MINI-16", "MINI-17"]},
                  {"id": "A2UI-W1", "provenance": "e7141d5569b6eb7813b13ccad0d8b4b44048492e", "status": "OTHER_LANE_SDK_NOT_RUN", "affects": ["RESULT-01", "MINI-16"]},
                  {"id": "MORPH-W1-002", "provenance": "Authenticated reference SHA256 51bb10cdf71ee1c10cac8108f602eee4b34e78967de23dc437985aa89db9bbbb", "status": "OTHER_LANE_MOVING_SOURCE_SNAPSHOT", "affects": ["INPUT-01", "INPUT-03"]}]}
    (OUTPUT / "feature-delta-278.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    changes = git("diff", "--name-status", "8f24983dc4e62cc52250858f0870826a3bc5f073", BASELINE).decode()
    (OUTPUT / "baseline-source-delta.tsv").write_text(changes, encoding="utf-8", newline="\n")
    (OUTPUT / "target-source-delta.tsv").write_text(git("diff", "--name-status", BASELINE, target_revision).decode(), encoding="utf-8", newline="\n")
    return result


def validate(document, original):
    errors = []
    expected = {r[0] for r in original}
    rows = document.get("rows", [])
    counts = Counter(row.get("id") for row in rows)
    if set(counts) != expected:
        errors.append(f"ID set mismatch: missing={sorted(expected - set(counts))}; unexpected={sorted(set(counts) - expected, key=str)}")
    if any(n != 1 for n in counts.values()) or len(rows) != 278:
        errors.append("duplicate IDs or incorrect 278 denominator")
    if document.get("historical_blob_sha256") != DIGEST or document.get("baseline") != BASELINE:
        errors.append("wrong provenance")
    target_revision = document.get("target_revision", BASELINE)
    if not isinstance(target_revision, str) or not re.fullmatch(r"[0-9a-f]{40}", target_revision):
        errors.append("invalid target revision")
        target_revision = BASELINE
    if "target_revision" in document:
        try:
            expected_project = {"path": "AI_HLY.xcodeproj/project.pbxproj", "revision": target_revision,
                "sha256": hashlib.sha256(git("show", f"{target_revision}:AI_HLY.xcodeproj/project.pbxproj")).hexdigest()}
            if document.get("target_project") != expected_project:
                errors.append("changed target project evidence")
        except subprocess.CalledProcessError:
            errors.append("invalid target project revision")
    originals = {r[0]: r[1:] for r in original}
    for row in rows:
        name = row.get("id")
        if name in originals and [row.get("historical_decision"), row.get("historical_feature"), row.get("historical_redesign_note")] != list(originals[name]):
            errors.append(f"{name}: historical row changed")
        if row.get("owner_target") not in {"AI", "MINIAPPS", "SHARED"}:
            errors.append(f"{name}: invalid owner")
        status = row.get("acceptance_status")
        if status not in {"EXECUTED_PASS", "REUSED_VERIFIED_PASS", "FAILED", "NOT_RUN", "BLOCKED"}:
            errors.append(f"{name}: invalid acceptance status")
        if status in {"EXECUTED_PASS", "REUSED_VERIFIED_PASS"} and not row.get("execution_evidence"):
            errors.append(f"{name}: PASS without execution evidence")
        for field in ["visibility", "retention", "availability", "migration", "permissions", "accessibility", "test_obligation", "unresolved_decision"]:
            if not isinstance(row.get(field), str) or not row[field].strip():
                errors.append(f"{name}: missing {field}")
        if not row.get("source_evidence"):
            errors.append(f"{name}: missing source evidence")
        for evidence in row.get("source_evidence", []):
            try:
                if evidence["level"] not in {"HISTORICAL_FILENAME_RESOLVED", "COMPONENT_ANCHOR_ONLY"} or evidence != anchor(evidence["path"], evidence["level"], target_revision):
                    errors.append(f"{name}: changed source anchor")
            except (KeyError, subprocess.CalledProcessError, UnicodeError):
                errors.append(f"{name}: invalid source anchor")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--target-revision", help="Exact commit to audit; generation defaults to current HEAD")
    args = parser.parse_args()
    document = generate(args.target_revision or git("rev-parse", "HEAD").decode().strip()) if args.generate else json.loads((OUTPUT / "feature-delta-278.json").read_text(encoding="utf-8"))
    _, original = historical()
    errors = validate(document, original)
    summary = {"status": "FAILED" if errors else "EXECUTED_PASS", "coverage_count": len(document["rows"]),
               "acceptance_counts": dict(Counter(r["acceptance_status"] for r in document["rows"])),
               "meaning": "Coverage/provenance validation only; no 278-feature behavior acceptance", "errors": errors}
    (OUTPUT / "coverage-results.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(summary))
    raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
