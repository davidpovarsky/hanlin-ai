#!/usr/bin/env python3
"""Compare original extension member bodies with their canonical SDK owners.

This is source-preservation evidence, not an Apple compile or runtime test.
Only listed localization and host-configuration adaptations are normalized.
"""
import argparse, difflib, hashlib, json, re, subprocess, tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--base", default="cfbe07d6cc4c5b8bc16f3e0fe477d0b8bf394b10")
parser.add_argument("--inspector", required=True, help="Compiled inspect_source_preservation.swift")
parser.add_argument("--report", required=True)
parser.add_argument("--git-user")
args = parser.parse_args()
git = (["sudo", "-n", "-u", args.git_user] if args.git_user else []) + ["git"]
pairs = {
    "ChavrusaChatShare/ShareViewController.swift": "Packages/HanlinAppExtensionsSDK/Sources/HanlinShareExtensionUI/HanlinShareViewController.swift",
    "ChavrusaChatNotificationService/NotificationService.swift": "Packages/HanlinAppExtensionsSDK/Sources/HanlinNotificationExtension/HanlinNotificationService.swift",
    "HanlinScriptingWidgets/HanlinScriptingWidgets.swift": "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingWidgets.swift",
    "HanlinScriptingWidgets/HanlinScriptingAppIntents.swift": "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingAppIntents.swift",
}
for name in ["TranslationProviderSession", "TranslationProviderRootView", "TranslationRoute", "TranslationProviderHomeView", "TranslationProviderAppsView", "TranslationProviderMiniChatView", "TranslationProviderMiniAppView"]:
    pairs[f"ChavrusaChatTranslationProvider/{name}.swift"] = f"Packages/HanlinAppExtensionsSDK/Sources/HanlinTranslationUI/{name}.swift"

literal = r'"(?:[^"\\]|\\.)*"'
def normalize(source):
    source = re.sub(r",\s*bundle:\s*HanlinLocalization\.bundle", "", source)
    source = re.sub(r"\b(Button|Label|Section|TextField|SecureField|Toggle|Menu|ContentUnavailableView)\(\s*hanlin:\s*", r"\1(", source)
    source = re.sub(r"(\.(?:navigationTitle|accessibilityLabel|accessibilityHint|alert|configurationDisplayName|description))\(Text\((" + literal + r")\)", r"\1(\2", source)
    source = re.sub(r"String\(localized:\s*(" + literal + r")\)", r"\1", source)
    source = re.sub(r'IntentDialog\(LocalizedStringResource\((' + literal + r'),\s*bundle:\s*\.atURL\(HanlinLocalization\.bundle\.bundleURL\)\)\)', r'\1', source)
    source = source.replace("try hostConfiguration.requireAppGroupIdentifier()", '"group.com.itorah.chavrusachat"')
    source = re.sub(r"if let category = hostConfiguration\.notificationCategoryIdentifier\s*\{\s*content\.categoryIdentifier = category\s*\}", 'content.categoryIdentifier = "CHAVRUSA_REMINDER"', source)
    source = source.replace("session.services.loadSnapshot()", "HanlinScriptExtensionStore().load()")
    return source

def inventory(path):
    result = subprocess.run([args.inspector, str(path)], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)

def key(name):
    return name.replace("HanlinShareViewController.", "ShareViewController.").replace("HanlinNotificationService.", "NotificationService.")

checks, provenance, prepared = [], [], []
with tempfile.TemporaryDirectory(prefix="hanlin-extension-provenance-") as temporary:
    temp = Path(temporary)
    for index, (original, canonical) in enumerate(pairs.items()):
        before = subprocess.run(git + ["show", args.base + ":" + original], check=True, capture_output=True).stdout
        after = Path(canonical).read_bytes()
        oldpath = temp / f"old{index}.swift"; oldpath.write_bytes(before)
        newpath = temp / f"new{index}.swift"; newpath.write_bytes(after)
        old = inventory(oldpath)
        new = {key(item["name"]): item for item in inventory(newpath)}
        provenance.append({"original": original, "canonical": canonical, "original_sha256": hashlib.sha256(before).hexdigest(), "canonical_sha256": hashlib.sha256(after).hexdigest()})
        for item in old:
            if item["name"] == "HanlinScriptingWidgetBundle.body":
                continue  # The OS @main declaration intentionally remains in its original target.
            match = new.get(item["name"])
            if match is None:
                checks.append({"original": original, "member": item["name"], "pass": False, "reason": "missing original member"})
                continue
            prepared.append((original, item["name"], item["kind"], normalize(item["source"]), normalize(match["source"])))
    for side, offset in [("old", 3), ("new", 4)]:
        fragments = []
        for index, row in enumerate(prepared):
            prefix = f"func proof{index}() " if row[2] == "function" else f"var proof{index}: Any "
            fragments.append(prefix + row[offset])
        (temp / (side + "-normalized.swift")).write_text("\n".join(fragments))
    old = {x["name"].split("(")[0]: x["tokens"] for x in inventory(temp / "old-normalized.swift")}
    new = {x["name"].split("(")[0]: x["tokens"] for x in inventory(temp / "new-normalized.swift")}
    for index, row in enumerate(prepared):
        before, after = old[f"proof{index}"], new[f"proof{index}"]
        passed = before == after
        check = {"original": row[0], "member": row[1], "pass": passed,
                 "normalized_tokens_sha256": hashlib.sha256(json.dumps(before, ensure_ascii=False).encode()).hexdigest()}
        if not passed:
            check["difference"] = list(difflib.unified_diff(before, after, fromfile="original", tofile="sdk"))[:70]
            print("DIFFERENT", row[0], row[1]); print("\n".join(check["difference"]))
        checks.append(check)

report = {"base": args.base, "scope": "Original function/computed-property bodies; access/constructors are separate public seams.",
          "normalizations": ["Canonical localization bundle and exact original control forwarding helpers", "Host-selected App Group and notification category", "Injected original snapshot-store loader"],
          "source_provenance": provenance, "checks": checks,
          "passed": sum(x["pass"] for x in checks), "total": len(checks),
          "apple_compilation": "Not performed by this source-preservation check", "device_acceptance": "Not claimed"}
Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(f"Preserved {report['passed']}/{report['total']} original member bodies across {len(pairs)} source owners")
raise SystemExit(0 if all(x["pass"] for x in checks) else 1)
