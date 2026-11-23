#!/usr/bin/env python3
"""Source-preservation evidence for the original MiniApps library and lifecycle.

This compares original member-body tokens, with only explicit resource and
injection seams normalized. It does not claim Apple compilation or UI acceptance.
"""
import argparse, difflib, hashlib, json, re, subprocess, tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--base", default="65fdc2ed9cd1ed563b86d98cee2dab7f665f714c")
parser.add_argument("--inspector", required=True)
parser.add_argument("--report", required=True)
parser.add_argument("--git-user")
args = parser.parse_args()
git = (["sudo", "-n", "-u", args.git_user] if args.git_user else []) + ["git"]
pairs = {
    "HanlinMiniAppsApp/MiniAppsLibrary.swift": ["Packages/HanlinPresentationSDK/Sources/HanlinMiniAppsUI/HanlinMiniAppsLibrary.swift"],
    "HanlinMiniAppsApp/MiniAppsServices.swift": ["Packages/HanlinPresentationSDK/Sources/HanlinMiniAppsUI/HanlinMiniAppsServices.swift",
        "AI_HLY/Downstream/ProductSplitIntegration/HanlinMiniAppsProvider.swift"],
    "HanlinMiniAppsApp/MiniAppsForegroundBridge.swift": ["AI_HLY/Downstream/ProductSplitIntegration/HanlinMiniAppsForegroundBridge.swift"],
}
literal = r'"(?:[^"\\]|\\.)*"'

def normalize(source):
    source = re.sub(r",\s*bundle:\s*HanlinLocalization\.bundle", "", source)
    source = re.sub(r"\b(Button|Label|Section|ContentUnavailableView|LabeledContent)\(\s*hanlin:\s*", r"\1(", source)
    source = re.sub(r"(\.(?:navigationTitle|alert))\(Text\((" + literal + r")\)", r"\1(\2", source)
    source = re.sub(r"prompt:\s*Text\((" + literal + r")\)", r"prompt: \1", source)
    source = source.replace("transferView()", "HanlinMiniAppTransferView(mode: .receive)")
    source = source.replace("isTransferringProductData()", "HanlinScriptingPlatform.shared.isTransferringProductData")
    return source

def inventory(path):
    return json.loads(subprocess.check_output([args.inspector, str(path)], text=True))

def key(name):
    name = name.replace("HanlinMiniAppsLibrary.", "MiniAppsLibrary.").replace("HanlinMiniAppsServices.", "MiniAppsServices.").replace("HanlinMiniAppsForegroundBridge.", "MiniAppsForegroundBridge.")
    return "MiniAppsServices." + name if name == "connected(to:)" else name

checks, provenance, prepared = [], [], []
with tempfile.TemporaryDirectory(prefix="hanlin-miniapps-provenance-") as temporary:
    temp = Path(temporary)
    for index, (original, canonical) in enumerate(pairs.items()):
        before = subprocess.check_output(git + ["show", args.base + ":" + original])
        oldpath = temp / f"old{index}.swift"; oldpath.write_bytes(before)
        old = inventory(oldpath)
        new = {key(item["name"]): item for path in canonical for item in inventory(Path(path))}
        provenance.append({"original": original, "original_sha256": hashlib.sha256(before).hexdigest(),
            "canonical": [{"path": path, "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest()} for path in canonical]})
        for item in old:
            match = new.get(item["name"])
            if match is None:
                checks.append({"original": original, "member": item["name"], "pass": False, "reason": "missing original member"})
                continue
            prepared.append((original, item["name"], item["kind"], normalize(item["source"]), normalize(match["source"])))
    for side, offset in [("old", 3), ("new", 4)]:
        fragments = [(f"func proof{index}() " if row[2] == "function" else f"var proof{index}: Any ") + row[offset]
                     for index, row in enumerate(prepared)]
        (temp / (side + "-normalized.swift")).write_text("\n".join(fragments))
    old = {x["name"].split("(")[0]: x["tokens"] for x in inventory(temp / "old-normalized.swift")}
    new = {x["name"].split("(")[0]: x["tokens"] for x in inventory(temp / "new-normalized.swift")}
    for index, row in enumerate(prepared):
        before, after = old[f"proof{index}"], new[f"proof{index}"]
        check = {"original": row[0], "member": row[1], "pass": before == after,
                 "normalized_tokens_sha256": hashlib.sha256(json.dumps(before, ensure_ascii=False).encode()).hexdigest()}
        if not check["pass"]:
            check["difference"] = list(difflib.unified_diff(before, after, fromfile="original", tofile="sdk"))[:70]
            print("DIFFERENT", row[0], row[1]); print("\n".join(check["difference"]))
        checks.append(check)

report = {"base": args.base,
          "scope": "Original function and computed-property bodies; new public constructors, immutable identity isolation and host callback storage are separate seams.",
          "normalizations": ["Canonical localization bundle and original control forwarding helpers",
                             "Injected exact original transfer view and live transfer-busy callback"],
          "source_provenance": provenance, "checks": checks,
          "passed": sum(x["pass"] for x in checks), "total": len(checks),
          "apple_compilation": "Not performed by this source-preservation check", "device_acceptance": "Not claimed"}
Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"Preserved {report['passed']}/{report['total']} original member bodies across {len(pairs)} source owners")
raise SystemExit(0 if all(x["pass"] for x in checks) else 1)
