#!/usr/bin/env python3
"""Reject damaged UI translations and verify the values actually packaged in an app."""
import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

CATALOGS = {
    "Localizable": ("AI_HLY/Resource/Localizable.xcstrings", [
        "The permission change could not be saved. Please try again.",
        "Remembered permissions apply across your conversations on this device. System permissions remain controlled in Settings.",
        "Revoke all tool permissions", "Revoke permission for %@", "Revoke permission",
        "Sensitive tools will ask before their first use.", "No remembered tool permissions",
        "Tool permissions", "Collapse",
        "This permission will also apply in your other conversations.",
        "Allow and remember", "Allowed and remembered", "Thought for %@", "Waiting for model response",
        "Allow once", "Deny", "Awaiting approval", "Allowed once", "Not approved",
        "Expanded", "Collapsed", "Working", "Reasoning", "Actions requiring your approval", "Searching the web for %@", "Searched the web for %@",
        "Request details are unavailable.", "Review this operation before allowing it once.",
        "Use current location", "Your current location", "Review request details",
        "Checking your location", "Checked your location", "Checking the weather", "Checked the weather",
        "Planning a route", "Planned a route", "Searching nearby places", "Searched nearby places",
        "Searching the calendar", "Searched the calendar", "Updating the calendar", "Updated the calendar",
        "Draft", "Image", "Yesterday", "Two days ago", "Response interrupted", "Response error: %@",
    ]),
    "RuntimeLocalizable": ("AI_HLY/Downstream/RuntimeCore/Resources/RuntimeLocalizable.xcstrings", [
        "Background continuation was not available before the system suspended the app.",
        "Waiting for a response", "Thinking", "Writing the response",
        "Waiting for your approval", "Response complete", "Response stopped",
    ]),
}
LOCALES = ("en", "he", "zh-Hans")

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key: " + key)
        result[key] = value
    return result

def values(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "value" and isinstance(value, str):
                yield value
            else:
                yield from values(value)
    elif isinstance(node, list):
        for value in node:
            yield from values(value)

def damaged(value):
    return bool(re.search(r"\?{2,}|\ufffd|[\x00-\x08\x0b\x0c\x0e-\x1f]", value))

def validate(root, revision=None, app=None):
    errors = []
    checked_values = 0
    checked_packaged_values = 0
    for table, (relative, required_keys) in CATALOGS.items():
        raw = (subprocess.check_output(["git", "show", revision + ":" + relative], cwd=root)
               if revision else (root / relative).read_bytes())
        data = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
        for key, entry in data["strings"].items():
            for locale, localization in entry.get("localizations", {}).items():
                for value in values(localization):
                    checked_values += 1
                    if damaged(value):
                        errors.append({"table": table, "key": key, "locale": locale, "reason": "damaged Unicode translation"})
        for key in required_keys:
            for locale in LOCALES:
                value = data["strings"].get(key, {}).get("localizations", {}).get(locale, {}).get("stringUnit", {}).get("value")
                if not isinstance(value, str) or not value:
                    errors.append({"table": table, "key": key, "locale": locale, "reason": "missing required UI translation"})
                    continue
                if value.count("%@") != key.count("%@"):
                    errors.append({"table": table, "key": key, "locale": locale, "reason": "format argument changed"})
                if locale == "he" and not re.search(r"[\u0590-\u05ff]", value):
                    errors.append({"table": table, "key": key, "locale": locale, "reason": "Hebrew text missing"})
                if locale == "zh-Hans" and not re.search(r"[\u3400-\u9fff]", value):
                    errors.append({"table": table, "key": key, "locale": locale, "reason": "Chinese text missing"})
                if app:
                    resource = app / (locale + ".lproj") / (table + ".strings")
                    if not resource.is_file():
                        errors.append({"table": table, "locale": locale, "reason": "packaged table missing"})
                        continue
                    packaged = plistlib.loads(resource.read_bytes())
                    checked_packaged_values += 1
                    if packaged.get(key) != value:
                        errors.append({"table": table, "key": key, "locale": locale, "reason": "packaged value differs from source"})
    result = {"status": "PASS" if not errors else "FAIL", "catalog_values": checked_values,
              "packaged_values": checked_packaged_values, "errors": errors}
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--git-ref", help="Read a historical revision without changing the worktree")
    parser.add_argument("--app", type=Path, help="Also verify compiled tables in this actual app bundle")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = validate(args.root, args.git_ref, args.app)
    encoded = json.dumps(result, ensure_ascii=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0 if result["status"] == "PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
